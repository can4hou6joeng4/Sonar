import AVFoundation
import Foundation
import MediaPlayer
import Observation
import OSLog
#if os(macOS)
import AppKit
#else
import UIKit
#endif

enum PlaybackFailureDiagnostics {
    static func sanitizedDetail(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }

        let lowercaseValue = value.lowercased()
        let sensitiveMarkers = [
            "://", "?", "&", "=", "token", "authorization", "cookie",
            "credential", "password", "secret", "signature", "chksz",
        ]
        guard !sensitiveMarkers.contains(where: lowercaseValue.contains),
              value.range(
                  of: #"(?:[A-Za-z0-9-]+\.)+[A-Za-z]{2,}(?::\d+)?/\S*"#,
                  options: .regularExpression
              ) == nil else { return nil }
        return value
    }

    static func message(for error: Error, fallback: String) -> String {
        sanitizedDetail(error.localizedDescription) ?? fallback
    }
}

struct PlaybackRecoveryGate: Sendable {
    private(set) var generation = 0
    private(set) var recoveryConsumed = false

    mutating func beginLoad() -> Int {
        generation += 1
        recoveryConsumed = false
        return generation
    }

    mutating func consumeRecovery(for generation: Int) -> Bool {
        guard self.generation == generation, !recoveryConsumed else { return false }
        recoveryConsumed = true
        return true
    }

    func isCurrent(_ generation: Int) -> Bool {
        self.generation == generation
    }
}

@MainActor
@Observable
public final class PlaybackService {
    public enum State: Equatable, Sendable {
        case idle
        case loading
        case playing
        case paused
        case failed(String)
    }

    public enum PlaybackMode: String, CaseIterable, Sendable {
        case sequence = "listLoop"
        case repeatOne
        case shuffle
        case playInOrder
    }

    /// 切换音质的结果。界面据此给出不同提示，不允许「点了没反应」。
    public enum QualityChange: Equatable, Sendable {
        case unchanged
        case reloaded(Quality)
        case deferred
        case failed(String)
    }

    private static let preferredQualityKey = "preferredPlaybackQuality"
    private static let qualityPolicyVersionKey = "playbackQualityPolicyVersion"
    private static let qualityPolicyVersion = 1
    private static let playbackModeKey = "playbackMode"
    private static let volumeKey = "macPlaybackVolume"

    /// App volume only; the Mac system output volume is left to the user.
    public private(set) var volume: Double

    public func setVolume(_ value: Double) {
        guard value.isFinite else { return }
        volume = min(1, max(0, value))
        player.volume = Float(volume)
        #if os(macOS)
        defaults.set(volume, forKey: Self.volumeKey)
        #endif
    }

    public private(set) var queue: PlaybackQueue
    public private(set) var activePlaylistID: UUID?
    public private(set) var state: State = .idle
    public private(set) var playbackMode: PlaybackMode
    public private(set) var elapsed: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    public private(set) var playbackRequested = false
    /// 用户选定的音质**上限**：解析器从这一档起逐级下降，所以它是起点而不是锁死值。
    public private(set) var preferredQuality: Quality {
        didSet { defaults.set(preferredQuality.rawValue, forKey: Self.preferredQualityKey) }
    }
    private let player: AVPlayer
    private let resolver: PlaybackURLResolving
    private let defaults: UserDefaults
    private var intentRevision = 0
    private let autoplaySkipDelay: @Sendable () async throws -> Void
    private let recoveryDelay: @Sendable () async throws -> Void
    private let randomIndex: @Sendable (Range<Int>) -> Int
    private var timeObserver: Any?
    private var timeControlObservation: NSKeyValueObservation?
    private var itemStatusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var stalledObserver: NSObjectProtocol?
    private var failedToEndObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var silenceHintObserver: NSObjectProtocol?
    private var didBecomeActiveObserver: NSObjectProtocol?
    public private(set) var shouldResumeAfterInterruption = false
    private var remoteCommandTokens: [(MPRemoteCommand, Any)] = []
    private var nowPlayingArtwork: MPMediaItemArtwork?
    private var currentMediaHost: String?
    private var recoveryGate = PlaybackRecoveryGate()
    #if os(iOS)
    private var transitionBackgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var isTransitionInProgress: Bool { transitionBackgroundTaskID != .invalid }
    #else
    private var isTransitionInProgress = false
    #endif
    private var consecutiveAutoplayFailures = 0
    private let maxConsecutiveAutoplaySkips = 3
    private var hasPrefetchedUpcomingForCurrentTrack = false
    private struct UpcomingResolution {
        let id = UUID()
        let musicID: String
        let quality: Quality
        let task: Task<URL, Error>
    }
    private var upcomingResolution: UpcomingResolution?
    private var activeURLResolutionTask: Task<URL, Error>?
    private var mediaPreparationTask: Task<Void, Never>?
    private var preparedNext: (id: UUID, item: AVPlayerItem)?
    private var preparedStatusObservation: NSKeyValueObservation?
    private var preparedBufferObservation: NSKeyValueObservation?
    private let logger = Logger(subsystem: "cn.bobochang.sonar", category: "PlaybackTransition")

    struct TransitionTiming {
        let id: Int
        let startedAt: TimeInterval
        var reusedPreparedItem = false
        var resolutionMilliseconds: Double?
        var readyMilliseconds: Double?
        var playingMilliseconds: Double?
    }
    private(set) var lastTransitionTiming: TransitionTiming?
    private var measuredItem: AVPlayerItem?

    private static func makePlayer() -> AVPlayer {
        #if os(macOS)
        return AVQueuePlayer()
        #else
        return AVPlayer()
        #endif
    }

    public init(
        player: AVPlayer? = nil,
        resolver: PlaybackURLResolving = PlaybackURLResolver(),
        defaults: UserDefaults = .standard,
        randomIndex: @escaping @Sendable (Range<Int>) -> Int = { Int.random(in: $0) },
        autoplaySkipDelay: @escaping @Sendable () async throws -> Void = {
            try await Task.sleep(for: .milliseconds(150))
        },
        recoveryDelay: @escaping @Sendable () async throws -> Void = {
            try await Task.sleep(for: .milliseconds(400))
        }
    ) {
        self.player = player ?? Self.makePlayer()
        let player = self.player
        // Keep queue ownership in PlaybackService. The next item buffers in
        // AVQueuePlayer, but only our end handler may advance it (mode/pause win).
        if player is AVQueuePlayer { player.actionAtItemEnd = .pause }
        #if os(macOS)
        let restoredVolume = (defaults.object(forKey: Self.volumeKey) as? NSNumber)?.doubleValue ?? Double(player.volume)
        let boundedVolume = restoredVolume.isFinite ? min(1, max(0, restoredVolume)) : 1
        volume = boundedVolume
        player.volume = Float(boundedVolume)
        #else
        volume = Double(player.volume)
        #endif
        self.resolver = resolver
        self.defaults = defaults
        self.recoveryDelay = recoveryDelay
        self.autoplaySkipDelay = autoplaySkipDelay
        self.randomIndex = randomIndex
        let restoredMode = defaults.string(forKey: Self.playbackModeKey)
            .flatMap(PlaybackMode.init(rawValue:)) ?? .sequence
        playbackMode = restoredMode
        queue = PlaybackQueue(randomIndex: randomIndex)
        // Apply highest-first once when upgrading; subsequent manual choices remain explicit.
        let migrateQuality = defaults.integer(forKey: Self.qualityPolicyVersionKey) < Self.qualityPolicyVersion
        preferredQuality = migrateQuality ? .master : defaults.string(forKey: Self.preferredQualityKey)
            .flatMap(Quality.init(rawValue:)) ?? .master
        if migrateQuality {
            defaults.set(preferredQuality.rawValue, forKey: Self.preferredQualityKey)
            defaults.set(Self.qualityPolicyVersion, forKey: Self.qualityPolicyVersionKey)
        }
        queue.setShuffled(restoredMode == .shuffle)
        installTimeObserver()
        installTimeControlObserver()
        installEndObserver()
        installFailureObservers()
        installRemoteCommands()
        installWidgetNotifications()
        installAudioSessionObservers()
    }

    deinit {
        MainActor.assumeIsolated {
            upcomingResolution?.task.cancel()
            activeURLResolutionTask?.cancel()
            mediaPreparationTask?.cancel()
            preparedStatusObservation?.invalidate()
            preparedBufferObservation?.invalidate()
            endTransitionBackgroundTask()
            removeWidgetNotifications()
            if let timeObserver { player.removeTimeObserver(timeObserver) }
            timeControlObservation?.invalidate()
            itemStatusObservation?.invalidate()
            if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
            if let stalledObserver { NotificationCenter.default.removeObserver(stalledObserver) }
            if let failedToEndObserver { NotificationCenter.default.removeObserver(failedToEndObserver) }
            if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
            if let routeChangeObserver { NotificationCenter.default.removeObserver(routeChangeObserver) }
            if let silenceHintObserver { NotificationCenter.default.removeObserver(silenceHintObserver) }
            if let didBecomeActiveObserver { NotificationCenter.default.removeObserver(didBecomeActiveObserver) }
            for (command, token) in remoteCommandTokens { command.removeTarget(token) }
        }
    }

    public func replaceQueue(
        _ tracks: [Track],
        startingAt index: Int? = nil,
        autoplay: Bool = true,
        activePlaylistID: UUID? = nil,
        preservingPlayedMusicIDs: Set<String> = []
    ) async {
        self.activePlaylistID = activePlaylistID
        consecutiveAutoplayFailures = 0
        discardUpcoming()
        shouldResumeAfterInterruption = false

        let startIndex: Int
        if let index {
            startIndex = index
        } else if playbackMode == .shuffle, tracks.count > 1 {
            startIndex = randomIndex(0..<tracks.count)
        } else {
            startIndex = 0
        }

        queue.replace(
            with: tracks,
            startingAt: startIndex,
            preservingPlayedMusicIDs: preservingPlayedMusicIDs
        )
        await loadCurrent(autoplay: autoplay)
    }

    @discardableResult
    public func shuffleAndPlay(
        _ tracks: [Track],
        startingAt index: Int? = nil,
        activePlaylistID: UUID? = nil
    ) async -> Bool {
        guard !tracks.isEmpty else { return false }
        consecutiveAutoplayFailures = 0
        let sameQueue = queue.hasSameTracks(as: tracks)
        setPlaybackMode(.shuffle)

        var preservedPlayedMusicIDs = sameQueue ? queue.shuffledPlayedMusicIDs : []

        let startIndex: Int
        if let index, tracks.indices.contains(index) {
            startIndex = index
        } else if tracks.count > 1 {
            let currentTrack = queue.current
            let currentIndex = tracks.firstIndex(where: { $0.musicID == currentTrack?.musicID })
            let candidateIndices: [Int]
            if let currentIndex, tracks.count > 1 {
                let filtered = tracks.indices.filter {
                    $0 != currentIndex
                        && !preservedPlayedMusicIDs.contains(tracks[$0].musicID)
                }
                candidateIndices = filtered.isEmpty ? Array(tracks.indices) : filtered
            } else {
                let filtered = tracks.indices.filter {
                    !preservedPlayedMusicIDs.contains(tracks[$0].musicID)
                }
                candidateIndices = filtered.isEmpty ? Array(tracks.indices) : filtered
            }
            if candidateIndices.allSatisfy({ preservedPlayedMusicIDs.contains(tracks[$0].musicID) }) {
                preservedPlayedMusicIDs.removeAll()
            }
            let offset = randomIndex(0..<candidateIndices.count)
            startIndex = candidateIndices.indices.contains(offset) ? candidateIndices[offset] : 0
        } else {
            startIndex = 0
        }

        await replaceQueue(
            tracks,
            startingAt: startIndex,
            autoplay: true,
            activePlaylistID: activePlaylistID,
            preservingPlayedMusicIDs: preservedPlayedMusicIDs
        )
        return true
    }

    public func onTrackAddedToPlaylist(_ track: Track, playlistID: UUID) {
        guard activePlaylistID == playlistID else { return }
        guard !queue.tracks.contains(where: { $0.musicID == track.musicID }) else { return }
        defer { prefetchUpcomingTrackIfNeeded() }

        if playbackMode == .shuffle {
            if let currentIndex = queue.currentIndex {
                queue.insert(track, at: currentIndex + 1)
            } else {
                queue.append(track)
            }
        } else {
            queue.append(track)
        }
    }

    public func onTrackRemovedFromPlaylist(_ track: Track, playlistID: UUID) {
        guard activePlaylistID == playlistID else { return }
        guard let index = queue.tracks.firstIndex(where: { $0.musicID == track.musicID }) else { return }
        if queue.currentIndex != index {
            queue.remove(at: index)
            prefetchUpcomingTrackIfNeeded()
        }
    }

    @discardableResult
    public func enqueue(_ track: Track) async -> Bool {
        guard !queue.tracks.contains(where: { $0.musicID == track.musicID }) else {
            return false
        }
        guard queue.current != nil else {
            let tracks = queue.tracks + [track]
            await replaceQueue(tracks, startingAt: tracks.count - 1, autoplay: false)
            return true
        }
        queue.append(track)
        prefetchUpcomingTrackIfNeeded()
        return true
    }

    public func playNext(_ track: Track) async {
        guard let currentIndex = queue.currentIndex else {
            _ = await enqueue(track)
            return
        }
        queue.insert(track, at: currentIndex + 1)
        prefetchUpcomingTrackIfNeeded()
    }

    public func play() async {
        intentRevision += 1
        shouldResumeAfterInterruption = false
        consecutiveAutoplayFailures = 0
        playbackRequested = true
        if player.currentItem == nil || player.currentItem?.status == .failed {
            await loadCurrent(autoplay: true, refreshing: player.currentItem?.status == .failed)
            return
        }
        do {
            try configureAudioSession()
            state = .loading
            player.play()
            synchronizePlaybackState()
            prefetchUpcomingTrackIfNeeded()
            updateNowPlaying()
        } catch {
            playbackRequested = false
            state = .failed(
                PlaybackFailureDiagnostics.message(for: error, fallback: "音频会话启动失败")
            )
        }
    }

    public func pause() {
        intentRevision += 1
        shouldResumeAfterInterruption = false
        playbackRequested = false
        player.pause()
        state = .paused
        endTransitionBackgroundTask()
        updateNowPlaying()
    }

    public func togglePlayback() async {
        if case .failed = state {
            await retryCurrent()
        } else if playbackRequested {
            pause()
        } else {
            await play()
        }
    }

    public func retryCurrent() async {
        guard queue.current != nil else { return }
        consecutiveAutoplayFailures = 0
        await loadCurrent(autoplay: true, refreshing: true)
    }

    public func setPlaybackMode(_ mode: PlaybackMode) {
        guard mode != playbackMode else { return }
        playbackMode = mode
        defaults.set(mode.rawValue, forKey: Self.playbackModeKey)
        queue.setShuffled(mode == .shuffle)
        logger.info("mode_changed mode=\(mode.rawValue, privacy: .public)")
        prefetchUpcomingTrackIfNeeded()
    }

    public func seek(to seconds: TimeInterval) async {
        let generation = recoveryGate.generation
        let item = player.currentItem
        let target = CMTime(seconds: max(0, min(seconds, duration)), preferredTimescale: 600)
        await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        guard !Task.isCancelled, recoveryGate.isCurrent(generation), item === player.currentItem else { return }
        elapsed = target.seconds
        updateNowPlaying()
    }

    public func next() async {
        beginTransitionBackgroundTask()
        consecutiveAutoplayFailures = 0
        guard queue.advance(wrapping: playbackMode != .playInOrder) != nil else {
            if playbackMode == .playInOrder { pause() }
            else { endTransitionBackgroundTask() }
            return
        }
        await loadCurrent(autoplay: true)
    }

    public func previous() async {
        beginTransitionBackgroundTask()
        consecutiveAutoplayFailures = 0
        guard queue.retreat(wrapping: playbackMode == .sequence || playbackMode == .repeatOne) != nil else {
            endTransitionBackgroundTask()
            await seek(to: 0)
            return
        }
        await loadCurrent(autoplay: true)
    }

    public func selectQueueItem(at index: Int) async {
        guard queue.tracks.indices.contains(index), queue.currentIndex != index else { return }
        consecutiveAutoplayFailures = 0
        queue.select(index: index)
        await loadCurrent(autoplay: true)
    }

    public func moveQueueItems(fromOffsets: IndexSet, toOffset: Int) {
        queue.move(fromOffsets: fromOffsets, toOffset: toOffset)
        prefetchUpcomingTrackIfNeeded()
    }

    public func insertQueueItem(_ track: Track, at index: Int) {
        queue.insert(track, at: index)
        prefetchUpcomingTrackIfNeeded()
    }

    public func removeQueueItem(at index: Int) async {
        let removedCurrent = queue.currentIndex == index
        _ = queue.remove(at: index)
        if removedCurrent { await loadCurrent(autoplay: playbackRequested) }
        else { prefetchUpcomingTrackIfNeeded() }
    }

    public func clearUpcoming() {
        queue.clearUpcoming()
        prefetchUpcomingTrackIfNeeded()
    }

    func handlePlaybackEnded(of item: AVPlayerItem) async {
        // Notifications cross a Task boundary. A later pause must win even if
        // the finished item is still installed when that task starts running.
        guard item === player.currentItem, playbackRequested else { return }
        await handlePlaybackEnded()
    }

    func handlePlaybackEnded() async {
        guard queue.currentIndex != nil else { return }

        beginTransitionBackgroundTask()
        try? configureAudioSession()
        consecutiveAutoplayFailures = 0

        switch playbackMode {
        case .playInOrder:
            guard queue.advance(wrapping: false) != nil else {
                pause()
                return
            }
            await loadCurrent(autoplay: true)
        case .sequence, .shuffle:
            guard queue.tracks.count > 1 else {
                await restartCurrent()
                return
            }
            guard queue.advance(wrapping: true) != nil else {
                endTransitionBackgroundTask()
                return
            }
            await loadCurrent(autoplay: true)
        case .repeatOne:
            await restartCurrent()
        }
    }

    public func updateNowPlayingArtwork(_ image: PlatformImage?) {
        nowPlayingArtwork = image.map { image in
            MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        #if os(iOS)
        if let image, let data = image.sonarJPEGData(compressionQuality: 0.8) {
            WidgetShareStore.shared.saveArtwork(data)
        } else if image == nil {
            WidgetShareStore.shared.clearArtwork()
        }
        #endif
        updateNowPlaying()
    }

    public func updateTrackMetadata(_ track: Track) {
        queue.updateTrack(track)
        updateNowPlaying()
    }

    /// 记下新的音质上限，并让当前曲目按它重新解析。
    /// 解析成功前不碰 `AVPlayer`，失败时旧的流还在播，只回滚状态并把原因交回界面。
    @discardableResult
    public func setPreferredQuality(_ quality: Quality) async -> QualityChange {
        guard preferredQuality != quality else { return .unchanged }
        preferredQuality = quality
        discardUpcoming()
        activeURLResolutionTask?.cancel()
        activeURLResolutionTask = nil
        guard let track = queue.current else { return .deferred }
        let generation = recoveryGate.beginLoad()

        let resumeAt = elapsed
        let previousState = state
        let revision = intentRevision
        state = .loading
        do {
            try track.source.requireEnabled()
            let url = try await resolver.musicURL(for: track, quality: quality)
            try Task.checkCancellation()
            guard recoveryGate.isCurrent(generation), queue.current?.musicID == track.musicID else {
                return .deferred
            }
            currentMediaHost = url.host
            let item = AVPlayerItem(url: url)
            replacePlayerItem(with: item)
            observeStatus(of: item, generation: generation)
            if resumeAt > 0 {
                // 用回调版而不是 await 版：新 item 还没 ready 时 await 会一直挂着，
                // 而我们只需要把起播点排进队列。
                player.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { _ in }
                elapsed = resumeAt
            } else {
                elapsed = 0
            }
            if playbackRequested {
                try configureAudioSession()
                player.play()
                synchronizePlaybackState()
            } else {
                playbackRequested = false
                state = .paused
            }
            prefetchUpcomingTrackIfNeeded()
            updateNowPlaying()
            return .reloaded(quality)
        } catch {
            guard recoveryGate.isCurrent(generation), queue.current?.musicID == track.musicID else {
                return .deferred
            }
            state = intentRevision == revision ? previousState : (playbackRequested ? .loading : .paused)
            if let item = player.currentItem { observeStatus(of: item, generation: generation) }
            synchronizePlaybackState()
            updateNowPlaying()
            if error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled { return .deferred }
            return .failed(
                PlaybackFailureDiagnostics.message(for: error, fallback: "无法切换音质")
            )
        }
    }

    private func loadCurrent(autoplay: Bool, refreshing: Bool = false) async {
        let generation = recoveryGate.beginLoad()
        lastTransitionTiming = TransitionTiming(id: generation, startedAt: ProcessInfo.processInfo.systemUptime)
        measuredItem = nil
        activeURLResolutionTask?.cancel()
        activeURLResolutionTask = nil
        intentRevision += 1
        shouldResumeAfterInterruption = false
        guard let track = queue.current else {
            discardUpcoming()
            playbackRequested = false
            replacePlayerItem(with: nil)
            currentMediaHost = nil
            itemStatusObservation?.invalidate()
            itemStatusObservation = nil
            elapsed = 0
            duration = 0
            state = .idle
            updateNowPlaying()
            endTransitionBackgroundTask()
            return
        }
        let quality = preferredQuality
        let prefetched = upcomingResolution.flatMap {
            !refreshing && $0.musicID == track.musicID && $0.quality == quality ? $0 : nil
        }
        let preparedItem: AVPlayerItem? = prefetched.flatMap { request in
            guard let preparedNext, preparedNext.id == request.id,
                  preparedNext.item.status != .failed,
                  let queuePlayer = player as? AVQueuePlayer,
                  queuePlayer.items().dropFirst().first === preparedNext.item else { return nil }
            return preparedNext.item
        }
        discardUpcoming(cancelResolution: prefetched == nil, removePreparedItem: preparedItem == nil)
        playbackRequested = autoplay
        if preparedItem == nil {
            player.pause()
            replacePlayerItem(with: nil)
        }
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        elapsed = 0
        duration = track.durationSeconds ?? 0
        state = .loading
        hasPrefetchedUpcomingForCurrentTrack = false
        updateNowPlaying()
        do {
            try track.source.requireEnabled()
            if let preparedItem, let asset = preparedItem.asset as? AVURLAsset {
                // No suspension between adopting the queued item and advancing:
                // a mode or queue edit cannot insert a different item ahead of it.
                try completeCurrentLoad(item: preparedItem, url: asset.url, generation: generation, prepared: true)
                return
            }
            // A next-track lookup can still be running when the user skips or
            // the current item ends. Transfer that work instead of duplicating it.
            let resolutionTask = Task { [resolver, prefetched] in
                if let prefetched {
                    do {
                        let url = try await withTaskCancellationHandler {
                            try await prefetched.task.value
                        } onCancel: {
                            prefetched.task.cancel()
                        }
                        try Task.checkCancellation()
                        return url
                    } catch {
                        // A speculative failure gets one ordinary on-demand
                        // attempt; a superseded load must not start more work.
                        try Task.checkCancellation()
                    }
                }
                try Task.checkCancellation()
                if refreshing, let refreshable = resolver as? PlaybackURLRefreshing {
                    return try await refreshable.refreshMusicURL(for: track, quality: quality)
                }
                return try await resolver.musicURL(for: track, quality: quality)
            }
            activeURLResolutionTask = resolutionTask
            defer {
                if recoveryGate.isCurrent(generation) { activeURLResolutionTask = nil }
            }
            let url = try await withTaskCancellationHandler {
                try await resolutionTask.value
            } onCancel: {
                resolutionTask.cancel()
            }
            try Task.checkCancellation()
            guard recoveryGate.isCurrent(generation), queue.current?.musicID == track.musicID else {
                return
            }
            try completeCurrentLoad(item: AVPlayerItem(url: url), url: url, generation: generation, prepared: false)
        } catch {
            guard recoveryGate.isCurrent(generation), queue.current?.musicID == track.musicID else {
                return
            }
            if error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled {
                playbackRequested = false
                player.pause()
                state = .paused
                updateNowPlaying()
                endTransitionBackgroundTask()
                return
            }
            let shouldSkip = playbackRequested && track.source.isEnabled
            let revision = intentRevision
            playbackRequested = false
            state = .failed(
                PlaybackFailureDiagnostics.message(for: error, fallback: "无法获取播放地址")
            )
            updateNowPlaying()
            if shouldSkip {
                await handleAutoplayFailureAndSkip(generation: generation, revision: revision)
            } else {
                endTransitionBackgroundTask()
            }
        }
    }

    private func completeCurrentLoad(item: AVPlayerItem, url: URL, generation: Int, prepared: Bool) throws {
        currentMediaHost = url.host
        measuredItem = item
        lastTransitionTiming?.reusedPreparedItem = prepared
        recordTransitionStage("resolved")
        if prepared, let queuePlayer = player as? AVQueuePlayer {
            queuePlayer.advanceToNextItem()
        } else {
            replacePlayerItem(with: item)
        }
        observeStatus(of: item, generation: generation)
        if playbackRequested {
            try configureAudioSession()
            player.play()
            synchronizePlaybackState()
            prefetchUpcomingTrackIfNeeded()
        } else {
            state = .paused
            endTransitionBackgroundTask()
        }
        updateNowPlaying()
    }

    private func handleAutoplayFailureAndSkip(generation: Int, revision: Int) async {
        consecutiveAutoplayFailures += 1
        guard consecutiveAutoplayFailures <= maxConsecutiveAutoplaySkips,
              queue.tracks.count > 1 else {
            consecutiveAutoplayFailures = 0
            endTransitionBackgroundTask()
            return
        }
        do {
            try await autoplaySkipDelay()
            try Task.checkCancellation()
        } catch {
            if recoveryGate.isCurrent(generation) { endTransitionBackgroundTask() }
            return
        }
        guard recoveryGate.isCurrent(generation), intentRevision == revision else { return }
        guard queue.advance(wrapping: playbackMode != .playInOrder) != nil else {
            endTransitionBackgroundTask()
            return
        }
        await loadCurrent(autoplay: true)
    }

    private func discardUpcoming(cancelResolution: Bool = true, removePreparedItem: Bool = true) {
        if cancelResolution { upcomingResolution?.task.cancel() }
        upcomingResolution = nil
        mediaPreparationTask?.cancel()
        mediaPreparationTask = nil
        preparedStatusObservation?.invalidate()
        preparedStatusObservation = nil
        preparedBufferObservation?.invalidate()
        preparedBufferObservation = nil
        if removePreparedItem, let preparedNext,
           let queuePlayer = player as? AVQueuePlayer,
           preparedNext.item !== queuePlayer.currentItem {
            queuePlayer.remove(preparedNext.item)
        }
        preparedNext = nil
    }

    private func replacePlayerItem(with item: AVPlayerItem?) {
        if let queuePlayer = player as? AVQueuePlayer {
            queuePlayer.removeAllItems()
            if let item { queuePlayer.insert(item, after: nil) }
        } else {
            player.replaceCurrentItem(with: item)
        }
    }

    private func prefetchUpcomingTrackIfNeeded() {
        guard playbackMode != .repeatOne,
              let nextTrack = queue.peekNext(wrapping: playbackMode != .playInOrder),
              nextTrack.source.isEnabled,
              nextTrack.musicID != queue.current?.musicID else {
            discardUpcoming()
            return
        }
        let quality = preferredQuality
        if upcomingResolution?.musicID == nextTrack.musicID, upcomingResolution?.quality == quality { return }
        discardUpcoming()
        guard playbackRequested, player.currentItem != nil else { return }
        let task = Task(priority: .userInitiated) { [resolver, nextTrack, quality] in
            try await resolver.musicURL(for: nextTrack, quality: quality)
        }
        let request = UpcomingResolution(musicID: nextTrack.musicID, quality: quality, task: task)
        upcomingResolution = request
        guard player is AVQueuePlayer else { return }
        mediaPreparationTask = Task { [weak self] in
            do {
                let url = try await task.value
                try Task.checkCancellation()
                guard let self, self.upcomingResolution?.id == request.id,
                      let queuePlayer = self.player as? AVQueuePlayer,
                      let currentItem = queuePlayer.currentItem else { return }
                let item = AVPlayerItem(url: url)
                item.preferredForwardBufferDuration = 5
                guard queuePlayer.canInsert(item, after: currentItem) else { return }
                self.preparedNext = (request.id, item)
                queuePlayer.insert(item, after: currentItem)
                self.logger.info("upcoming_media_enqueued")
                self.preparedBufferObservation = item.observe(\.loadedTimeRanges, options: [.initial, .new]) { [weak self, weak item] _, _ in
                    Task { @MainActor [weak self, weak item] in
                        guard let self, let item, self.preparedNext?.item === item,
                              self.preparedBufferObservation != nil,
                              item.loadedTimeRanges.contains(where: { $0.timeRangeValue.duration.seconds > 0 }) else { return }
                        self.logger.info("upcoming_media_buffered")
                        self.preparedBufferObservation?.invalidate()
                        self.preparedBufferObservation = nil
                    }
                }
                self.preparedStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self, weak item] _, _ in
                    Task { @MainActor [weak self, weak item] in
                        guard let self, let item, self.preparedNext?.item === item else { return }
                        if item.status == .readyToPlay {
                            self.logger.info("upcoming_media_ready")
                        } else if item.status == .failed {
                            // Keep the resolved URL for the ordinary load/recovery
                            // path, but never transfer a failed speculative item.
                            queuePlayer.remove(item)
                            self.preparedNext = nil
                            self.preparedStatusObservation = nil
                            self.preparedBufferObservation?.invalidate()
                            self.preparedBufferObservation = nil
                            self.logger.info("upcoming_media_failed")
                        }
                    }
                }
            } catch {
                // Speculation is optional. loadCurrent retries on demand.
            }
        }
    }

    private func recordTransitionStage(_ stage: String) {
        guard var timing = lastTransitionTiming else { return }
        let milliseconds = (ProcessInfo.processInfo.systemUptime - timing.startedAt) * 1_000
        switch stage {
        case "resolved":
            guard timing.resolutionMilliseconds == nil else { return }
            timing.resolutionMilliseconds = milliseconds
        case "ready":
            guard timing.readyMilliseconds == nil else { return }
            timing.readyMilliseconds = milliseconds
        case "playing":
            guard timing.playingMilliseconds == nil else { return }
            timing.playingMilliseconds = milliseconds
        default: return
        }
        lastTransitionTiming = timing
        logger.info("transition=\(timing.id) stage=\(stage, privacy: .public) elapsed_ms=\(milliseconds) prepared=\(timing.reusedPreparedItem)")
    }

    private func beginTransitionBackgroundTask() {
        endTransitionBackgroundTask()
        #if os(iOS)
        transitionBackgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "sonar-track-transition") { [weak self] in
            Task { @MainActor [weak self] in
                self?.endTransitionBackgroundTask()
            }
        }
        #else
        isTransitionInProgress = true
        #endif
    }

    private func endTransitionBackgroundTask() {
        #if os(iOS)
        if transitionBackgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(transitionBackgroundTaskID)
            transitionBackgroundTaskID = .invalid
        }
        #else
        isTransitionInProgress = false
        #endif
    }

    private func restartCurrent() async {
        let generation = recoveryGate.generation
        let revision = intentRevision
        await player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        guard !Task.isCancelled, recoveryGate.isCurrent(generation), intentRevision == revision else { return }
        elapsed = 0
        await play()
        endTransitionBackgroundTask()
    }

    private func configureAudioSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
        #endif
    }

    private func installAudioSessionObservers() {
        #if os(iOS)
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.handleAudioSessionInterruption(notification)
            }
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.handleAudioSessionRouteChange(notification)
            }
        }

        silenceHintObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.silenceSecondaryAudioHintNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                self?.handleAudioSessionSilenceHint(notification)
            }
        }

        didBecomeActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleAppDidBecomeActive()
            }
        }
        #endif
    }

    #if os(iOS)
    func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            intentRevision += 1
            let wasActive = playbackRequested
                || state == .playing
                || player.timeControlStatus == .playing
                || player.rate > 0
            if wasActive {
                shouldResumeAfterInterruption = true
            }
            playbackRequested = false
            player.pause()
            state = .paused
            updateNowPlaying()

        case .ended:
            guard shouldResumeAfterInterruption else { return }
            scheduleInterruptionResume()

        @unknown default:
            break
        }
    }

    func handleAudioSessionRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        if reason == .oldDeviceUnavailable {
            shouldResumeAfterInterruption = false
            pause()
        }
    }

    func handleAudioSessionSilenceHint(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionSilenceSecondaryAudioHintTypeKey] as? UInt,
              let hintType = AVAudioSession.SilenceSecondaryAudioHintType(rawValue: typeValue) else {
            return
        }

        switch hintType {
        case .begin:
            intentRevision += 1
            let wasActive = playbackRequested
                || state == .playing
                || player.timeControlStatus == .playing
                || player.rate > 0
            if wasActive {
                shouldResumeAfterInterruption = true
                playbackRequested = false
                player.pause()
                state = .paused
                updateNowPlaying()
            }
        case .end:
            guard shouldResumeAfterInterruption else { return }
            scheduleInterruptionResume()
        @unknown default:
            break
        }
    }

    #endif

    private func handleAppDidBecomeActive() {
        guard shouldResumeAfterInterruption else { return }
        scheduleInterruptionResume()
    }

    private func scheduleInterruptionResume() {
        let generation = recoveryGate.generation
        let revision = intentRevision
        Task { [weak self] in
            await self?.resumeAfterInterruption(generation: generation, revision: revision)
        }
    }

    private func resumeAfterInterruption(generation: Int, revision: Int) async {
        guard queue.current != nil else { return }
        var activated = false
        for attempt in 0..<4 {
            guard !Task.isCancelled, recoveryGate.isCurrent(generation), intentRevision == revision else { return }
            do {
                try configureAudioSession()
                activated = true
                break
            } catch {
                if attempt < 3 {
                    let delays: [UInt64] = [60_000_000, 180_000_000, 350_000_000]
                    try? await Task.sleep(nanoseconds: delays[attempt])
                }
            }
        }
        guard activated, !Task.isCancelled, recoveryGate.isCurrent(generation), intentRevision == revision else { return }
        shouldResumeAfterInterruption = false

        playbackRequested = true
        if let currentItem = player.currentItem, currentItem.status == .readyToPlay {
            state = .playing
            player.playImmediately(atRate: 1.0)
            synchronizePlaybackState()
            updateNowPlaying()
        } else {
            await play()
        }
    }

    private func installTimeObserver() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.elapsed = time.seconds.isFinite ? max(0, time.seconds) : 0
                self.synchronizePlaybackState()
                if let itemDuration = self.player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
                    self.duration = itemDuration
                }
                self.updateNowPlaying(includeWidget: false)

                if !self.hasPrefetchedUpcomingForCurrentTrack,
                   (self.elapsed >= 5.0 || (self.duration > 0 && self.duration - self.elapsed <= 25.0)) {
                    self.hasPrefetchedUpcomingForCurrentTrack = true
                    self.prefetchUpcomingTrackIfNeeded()
                }
            }
        }
    }

    private func installTimeControlObserver() {
        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.synchronizePlaybackState()
            }
        }
    }

    private func observeStatus(of item: AVPlayerItem, generation: Int) {
        itemStatusObservation?.invalidate()
        itemStatusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self, weak item] _, _ in
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, item === player.currentItem,
                      recoveryGate.isCurrent(generation) else { return }
                if item === measuredItem, item.status == .readyToPlay {
                    recordTransitionStage("ready")
                }
                if item.status == .failed {
                    await handlePlaybackFailure(
                        of: item,
                        generation: generation,
                        fallback: "音频加载失败"
                    )
                } else {
                    synchronizePlaybackState()
                }
                updateNowPlaying()
            }
        }
    }

    func handlePlaybackFailure(of item: AVPlayerItem, fallback: String) async {
        await handlePlaybackFailure(of: item, generation: recoveryGate.generation, fallback: fallback)
    }

    private func handlePlaybackFailure(
        of item: AVPlayerItem,
        generation: Int,
        fallback: String
    ) async {
        guard item === player.currentItem,
              recoveryGate.isCurrent(generation),
              let track = queue.current else { return }
        guard recoveryGate.consumeRecovery(for: generation) else {
            let shouldSkip = playbackRequested && isTransitionInProgress
            let revision = intentRevision
            playbackRequested = false
            state = .failed(playbackFailureDescription(for: item, fallback: fallback))
            updateNowPlaying()
            if shouldSkip {
                await handleAutoplayFailureAndSkip(generation: generation, revision: revision)
            } else {
                endTransitionBackgroundTask()
            }
            return
        }

        let trackID = track.musicID
        let queueIndex = queue.currentIndex
        let resumeAt = elapsed
        state = .loading
        discardUpcoming()
        player.pause()
        replacePlayerItem(with: nil)
        currentMediaHost = nil
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        elapsed = resumeAt
        updateNowPlaying()

        do {
            try await recoveryDelay()
            try Task.checkCancellation()
        } catch {
            guard recoveryGate.isCurrent(generation) else { return }
            playbackRequested = false
            state = .paused
            updateNowPlaying()
            endTransitionBackgroundTask()
            return
        }
        guard recoveryGate.isCurrent(generation),
              queue.currentIndex == queueIndex,
              queue.current?.musicID == trackID else { return }

        do {
            let url: URL
            if let refreshable = resolver as? PlaybackURLRefreshing {
                url = try await refreshable.refreshMusicURL(for: track, quality: preferredQuality)
            } else {
                url = try await resolver.musicURL(for: track, quality: preferredQuality)
            }
            try Task.checkCancellation()
            guard recoveryGate.isCurrent(generation),
                  queue.currentIndex == queueIndex,
                  queue.current?.musicID == trackID else { return }

            currentMediaHost = url.host
            let replacement = AVPlayerItem(url: url)
            replacePlayerItem(with: replacement)
            observeStatus(of: replacement, generation: generation)
            if resumeAt > 0 {
                player.seek(
                    to: CMTime(seconds: resumeAt, preferredTimescale: 600),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                ) { _ in }
                elapsed = resumeAt
            }
            if playbackRequested {
                try configureAudioSession()
                player.play()
                synchronizePlaybackState()
            } else {
                state = .paused
            }
            prefetchUpcomingTrackIfNeeded()
            updateNowPlaying()
        } catch {
            guard recoveryGate.isCurrent(generation),
                  queue.currentIndex == queueIndex,
                  queue.current?.musicID == trackID else { return }
            if error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled {
                playbackRequested = false
                state = .paused
                updateNowPlaying()
                endTransitionBackgroundTask()
                return
            }
            let shouldSkip = playbackRequested && isTransitionInProgress
            let revision = intentRevision
            elapsed = resumeAt
            playbackRequested = false
            state = .failed(
                PlaybackFailureDiagnostics.message(for: error, fallback: fallback)
            )
            updateNowPlaying()
            if shouldSkip {
                await handleAutoplayFailureAndSkip(generation: generation, revision: revision)
            } else {
                endTransitionBackgroundTask()
            }
        }
    }

    private func installFailureObservers() {
        stalledObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemPlaybackStalled,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self,
                      notification.object as? AVPlayerItem === player.currentItem,
                      playbackRequested else { return }
                if case .failed = state { return }
                if shouldResumeAfterInterruption { return }
                state = .loading
                updateNowPlaying()
            }
        }

        failedToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self, notification.object as? AVPlayerItem === player.currentItem else { return }
                guard let item = player.currentItem else { return }
                let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                if shouldResumeAfterInterruption || isInterruptionError(error) {
                    shouldResumeAfterInterruption = true
                    state = .paused
                    player.pause()
                    updateNowPlaying()
                    return
                }
                await handlePlaybackFailure(
                    of: item,
                    generation: recoveryGate.generation,
                    fallback: "音频播放中断"
                )
            }
        }
    }

    private func isInterruptionError(_ error: Error?) -> Bool {
        guard let error = error as NSError? else { return false }
        #if os(iOS)
        if error.domain == AVFoundationErrorDomain {
            if error.code == AVError.sessionWasInterrupted.rawValue
                || error.code == AVError.operationNotAllowed.rawValue {
                return true
            }
        }
        #endif
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            if isInterruptionError(underlying) { return true }
        }
        if error.domain == NSOSStatusErrorDomain && (error.code == 560557684 || error.code == 561017449) {
            return true
        }
        return false
    }

    func synchronizePlaybackState() {
        guard queue.current != nil, let item = player.currentItem else { return }
        if case .failed = state { return }
        if item.status == .failed {
            // 失败由 observeStatus / handlePlaybackFailure 负责处理，避免将失败状态覆写为 loading
            return
        }
        guard playbackRequested else {
            state = .paused
            return
        }
        if player.timeControlStatus == .playing, item.status == .readyToPlay {
            if item === measuredItem {
                recordTransitionStage("ready")
                recordTransitionStage("playing")
            }
            consecutiveAutoplayFailures = 0
            endTransitionBackgroundTask()
            state = .playing
        } else if player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
            state = .loading
        } else if player.timeControlStatus == .paused {
            if shouldResumeAfterInterruption {
                state = .paused
            } else if let error = player.error ?? item.error {
                if isInterruptionError(error) {
                    shouldResumeAfterInterruption = true
                    state = .paused
                } else {
                    state = .failed(playbackFailureDescription(for: item, fallback: "音频播放中断"))
                }
            } else {
                state = .loading
            }
        } else {
            state = .loading
        }
    }

    private func playbackFailureDescription(for item: AVPlayerItem?, fallback: String) -> String {
        var details: [String] = []

        func append(_ value: String?) {
            guard let value = PlaybackFailureDiagnostics.sanitizedDetail(value),
                  !details.contains(value) else { return }
            details.append(value)
        }

        append(fallback)
        append(currentMediaHost.map { "媒体主机 \($0)" })
        if let error = item?.error as NSError? {
            append(error.localizedFailureReason)
            if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
                append(underlying.localizedDescription)
                append(underlying.localizedFailureReason)
                if details.count == 1 {
                    append("\(underlying.domain) \(underlying.code)")
                }
            } else if details.count == 1 {
                append("\(error.domain) \(error.code)")
            }
        }
        if let event = item?.errorLog()?.events.last {
            if event.errorStatusCode != 0 {
                append("媒体响应状态 \(event.errorStatusCode)")
            }
        }
        return details.joined(separator: "；")
    }

    private func installEndObserver() {
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self, let item = notification.object as? AVPlayerItem else { return }
                await handlePlaybackEnded(of: item)
            }
        }
    }

    private func installRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        center.previousTrackCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true

        addTarget(center.playCommand) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.play() }
            return .success
        }
        addTarget(center.pauseCommand) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pause() }
            return .success
        }
        addTarget(center.togglePlayPauseCommand) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.togglePlayback() }
            return .success
        }
        addTarget(center.nextTrackCommand) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.next() }
            return .success
        }
        addTarget(center.previousTrackCommand) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.previous() }
            return .success
        }
        addTarget(center.changePlaybackPositionCommand) { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in await self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func addTarget(_ command: MPRemoteCommand, handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) {
        let token = command.addTarget(handler: handler)
        remoteCommandTokens.append((command, token))
    }

    private func updateNowPlaying(includeWidget: Bool = true) {
        #if os(macOS)
        let center = MPNowPlayingInfoCenter.default()
        if queue.current == nil {
            center.playbackState = .stopped
        } else {
            center.playbackState = state == .playing ? .playing : .paused
        }
        #endif
        guard let track = queue.current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            if includeWidget {
                updateWidgetSnapshot(for: nil)
            }
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: state == .playing ? 1.0 : 0.0,
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let nowPlayingArtwork { info[MPMediaItemPropertyArtwork] = nowPlayingArtwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        if includeWidget {
            updateWidgetSnapshot(for: track)
        }
    }

    private func updateWidgetSnapshot(for track: Track?) {
        #if os(iOS)
        let currentSnapshot = WidgetShareStore.shared.loadSnapshot()
        guard let track else {
            let emptySnapshot = WidgetPlaybackSnapshot(
                title: "暂无播放",
                artist: "点按开启随心听",
                album: "",
                quality: "",
                isPlaying: false,
                hasTrack: false,
                favoritesCount: currentSnapshot.favoritesCount,
                updatedAt: Date()
            )
            WidgetShareStore.shared.saveSnapshot(emptySnapshot)
            return
        }

        let qualityString: String
        switch preferredQuality {
        case .master: qualityString = "最高优先"
        case .hiRes: qualityString = "Hi-Res"
        case .lossless: qualityString = "无损"
        case .high: qualityString = "320K"
        case .standard: qualityString = "标准"
        }

        let updatedSnapshot = WidgetPlaybackSnapshot(
            title: track.title,
            artist: track.artist,
            album: track.album,
            quality: qualityString,
            isPlaying: state == .playing,
            hasTrack: true,
            favoritesCount: currentSnapshot.favoritesCount,
            updatedAt: Date()
        )
        WidgetShareStore.shared.saveSnapshot(updatedSnapshot)
        #endif
    }

    private func installWidgetNotifications() {
        #if os(iOS)
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        let names: [String] = [
            "cn.bobochang.sonar.remote.togglePlay",
            "cn.bobochang.sonar.remote.next",
            "cn.bobochang.sonar.remote.previous",
            "cn.bobochang.sonar.remote.play",
            "cn.bobochang.sonar.remote.pause"
        ]
        for name in names {
            CFNotificationCenterAddObserver(
                center,
                observer,
                { _, observer, name, _, _ in
                    guard let observer, let name else { return }
                    let service = Unmanaged<PlaybackService>.fromOpaque(observer).takeUnretainedValue()
                    let action = name.rawValue as String
                    Task { @MainActor in
                        switch action {
                        case "cn.bobochang.sonar.remote.togglePlay":
                            await service.togglePlayback()
                        case "cn.bobochang.sonar.remote.next":
                            await service.next()
                        case "cn.bobochang.sonar.remote.previous":
                            await service.previous()
                        case "cn.bobochang.sonar.remote.play":
                            await service.play()
                        case "cn.bobochang.sonar.remote.pause":
                            service.pause()
                        default:
                            break
                        }
                    }
                },
                name as CFString,
                nil,
                .deliverImmediately
            )
        }
        #endif
    }

    private func removeWidgetNotifications() {
        #if os(iOS)
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterRemoveEveryObserver(center, observer)
        #endif
    }
}
