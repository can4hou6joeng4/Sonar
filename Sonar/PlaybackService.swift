import AVFoundation
import Foundation
import MediaPlayer
import Observation
import UIKit

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
    }

    /// 切换音质的结果。界面据此给出不同提示，不允许「点了没反应」。
    public enum QualityChange: Equatable, Sendable {
        case unchanged
        case reloaded(Quality)
        case deferred
        case failed(String)
    }

    private static let preferredQualityKey = "preferredPlaybackQuality"
    private static let playbackModeKey = "playbackMode"

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
    public private(set) var shouldResumeAfterInterruption = false
    private var remoteCommandTokens: [(MPRemoteCommand, Any)] = []
    private var nowPlayingArtwork: MPMediaItemArtwork?
    private var currentMediaHost: String?
    private var recoveryGate = PlaybackRecoveryGate()
    private var transitionBackgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    private var consecutiveAutoplayFailures = 0
    private let maxConsecutiveAutoplaySkips = 3
    private var hasPrefetchedUpcomingForCurrentTrack = false
    private var preloadedNextURL: (musicID: String, url: URL)?
    private var prefetchTask: Task<Void, Never>?

    public init(
        player: AVPlayer = AVPlayer(),
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
        self.player = player
        self.resolver = resolver
        self.defaults = defaults
        self.recoveryDelay = recoveryDelay
        self.autoplaySkipDelay = autoplaySkipDelay
        self.randomIndex = randomIndex
        let restoredMode = defaults.string(forKey: Self.playbackModeKey)
            .flatMap(PlaybackMode.init(rawValue:)) ?? .sequence
        playbackMode = restoredMode
        queue = PlaybackQueue(randomIndex: randomIndex)
        preferredQuality = defaults.string(forKey: Self.preferredQualityKey)
            .flatMap(Quality.init(rawValue:)) ?? .hiRes
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
            for (command, token) in remoteCommandTokens { command.removeTarget(token) }
        }
    }

    public func replaceQueue(
        _ tracks: [Track],
        startingAt index: Int? = nil,
        autoplay: Bool = true,
        activePlaylistID: UUID? = nil
    ) async {
        self.activePlaylistID = activePlaylistID
        consecutiveAutoplayFailures = 0
        preloadedNextURL = nil
        prefetchTask?.cancel()
        shouldResumeAfterInterruption = false

        let startIndex: Int
        if let index {
            startIndex = index
        } else if playbackMode == .shuffle, tracks.count > 1 {
            startIndex = randomIndex(0..<tracks.count)
        } else {
            startIndex = 0
        }

        queue.replace(with: tracks, startingAt: startIndex)
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
        setPlaybackMode(.shuffle)

        let startIndex: Int
        if let index, tracks.indices.contains(index) {
            startIndex = index
        } else if tracks.count > 1 {
            let currentTrack = queue.current
            let currentIndex = tracks.firstIndex(where: { $0.musicID == currentTrack?.musicID })
            let candidateIndices: [Int]
            if let currentIndex, tracks.count > 1 {
                let filtered = tracks.indices.filter { $0 != currentIndex }
                candidateIndices = filtered.isEmpty ? Array(tracks.indices) : filtered
            } else {
                candidateIndices = Array(tracks.indices)
            }
            let offset = randomIndex(0..<candidateIndices.count)
            startIndex = candidateIndices.indices.contains(offset) ? candidateIndices[offset] : 0
        } else {
            startIndex = 0
        }

        await replaceQueue(tracks, startingAt: startIndex, autoplay: true, activePlaylistID: activePlaylistID)
        return true
    }

    public func onTrackAddedToPlaylist(_ track: Track, playlistID: UUID) {
        guard activePlaylistID == playlistID else { return }
        guard !queue.tracks.contains(where: { $0.musicID == track.musicID }) else { return }

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
        return true
    }

    public func playNext(_ track: Track) async {
        guard let currentIndex = queue.currentIndex else {
            _ = await enqueue(track)
            return
        }
        queue.insert(track, at: currentIndex + 1)
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
        guard queue.advance(wrapping: true) != nil else {
            endTransitionBackgroundTask()
            return
        }
        await loadCurrent(autoplay: true)
    }

    public func previous() async {
        beginTransitionBackgroundTask()
        consecutiveAutoplayFailures = 0
        guard queue.retreat(wrapping: playbackMode != .shuffle) != nil else {
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
    }

    public func insertQueueItem(_ track: Track, at index: Int) {
        queue.insert(track, at: index)
    }

    public func removeQueueItem(at index: Int) async {
        let removedCurrent = queue.currentIndex == index
        _ = queue.remove(at: index)
        if removedCurrent { await loadCurrent(autoplay: playbackRequested) }
    }

    public func clearUpcoming() {
        queue.clearUpcoming()
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

    public func updateNowPlayingArtwork(_ image: UIImage?) {
        nowPlayingArtwork = image.map { image in
            MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        if let image, let data = image.jpegData(compressionQuality: 0.8) {
            WidgetShareStore.shared.saveArtwork(data)
        } else if image == nil {
            WidgetShareStore.shared.clearArtwork()
        }
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
        guard let track = queue.current else { return .deferred }
        let generation = recoveryGate.beginLoad()

        let resumeAt = elapsed
        let previousState = state
        let revision = intentRevision
        state = .loading
        do {
            let url = try await resolver.musicURL(for: track, quality: quality)
            try Task.checkCancellation()
            guard recoveryGate.isCurrent(generation), queue.current?.musicID == track.musicID else {
                return .deferred
            }
            currentMediaHost = url.host
            let item = AVPlayerItem(url: url)
            player.replaceCurrentItem(with: item)
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
        intentRevision += 1
        shouldResumeAfterInterruption = false
        guard let track = queue.current else {
            playbackRequested = false
            player.replaceCurrentItem(with: nil)
            currentMediaHost = nil
            itemStatusObservation?.invalidate()
            itemStatusObservation = nil
            elapsed = 0
            duration = 0
            state = .idle
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            endTransitionBackgroundTask()
            return
        }
        playbackRequested = autoplay
        player.pause()
        player.replaceCurrentItem(with: nil)
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        elapsed = 0
        duration = track.durationSeconds ?? 0
        state = .loading
        hasPrefetchedUpcomingForCurrentTrack = false
        updateNowPlaying()
        do {
            let url: URL
            if !refreshing, preloadedNextURL?.musicID == track.musicID {
                url = preloadedNextURL!.url
                preloadedNextURL = nil
            } else if refreshing, let refreshable = resolver as? PlaybackURLRefreshing {
                url = try await refreshable.refreshMusicURL(for: track, quality: preferredQuality)
            } else {
                url = try await resolver.musicURL(for: track, quality: preferredQuality)
            }
            try Task.checkCancellation()
            guard recoveryGate.isCurrent(generation), queue.current?.musicID == track.musicID else {
                return
            }
            currentMediaHost = url.host
            itemStatusObservation?.invalidate()
            itemStatusObservation = nil
            let item = AVPlayerItem(url: url)
            player.replaceCurrentItem(with: item)
            observeStatus(of: item, generation: generation)
            updateNowPlaying()
            if playbackRequested {
                try configureAudioSession()
                player.play()
                synchronizePlaybackState()
                prefetchUpcomingTrackIfNeeded()
            } else {
                playbackRequested = false
                state = .paused
                endTransitionBackgroundTask()
            }
            updateNowPlaying()
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
            let shouldSkip = playbackRequested
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
        guard recoveryGate.isCurrent(generation), intentRevision == revision,
              queue.advance(wrapping: true) != nil else { return }
        await loadCurrent(autoplay: true)
    }

    private func prefetchUpcomingTrackIfNeeded() {
        guard let nextTrack = queue.peekNext(), nextTrack.musicID != queue.current?.musicID else { return }
        if preloadedNextURL?.musicID == nextTrack.musicID { return }
        prefetchTask?.cancel()
        prefetchTask = Task(priority: .userInitiated) { [weak self, nextTrack] in
            guard let self else { return }
            do {
                let url = try await self.resolver.musicURL(for: nextTrack, quality: self.preferredQuality)
                await MainActor.run {
                    if self.queue.peekNext()?.musicID == nextTrack.musicID {
                        self.preloadedNextURL = (nextTrack.musicID, url)
                    }
                }
            } catch {
                // Prefetch failure is silent; fallback will resolve on demand
            }
        }
    }

    private func beginTransitionBackgroundTask() {
        endTransitionBackgroundTask()
        transitionBackgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "sonar-track-transition") { [weak self] in
            Task { @MainActor [weak self] in
                self?.endTransitionBackgroundTask()
            }
        }
    }

    private func endTransitionBackgroundTask() {
        if transitionBackgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(transitionBackgroundTaskID)
            transitionBackgroundTaskID = .invalid
        }
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
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
    }

    private func installAudioSessionObservers() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleAudioSessionInterruption(notification)
            }
        }

        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleAudioSessionRouteChange(notification)
            }
        }

        silenceHintObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.silenceSecondaryAudioHintNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                self?.handleAudioSessionSilenceHint(notification)
            }
        }
    }

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
            if wasActive {
                shouldResumeAfterInterruption = true
            }
            playbackRequested = false
            player.pause()
            state = .paused
            updateNowPlaying()

        case .ended:
            guard shouldResumeAfterInterruption else { return }
            shouldResumeAfterInterruption = false
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
            if wasActive {
                shouldResumeAfterInterruption = true
                playbackRequested = false
                player.pause()
                state = .paused
                updateNowPlaying()
            }
        case .end:
            guard shouldResumeAfterInterruption else { return }
            shouldResumeAfterInterruption = false
            scheduleInterruptionResume()
        @unknown default:
            break
        }
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
        for attempt in 0..<3 {
            guard !Task.isCancelled, recoveryGate.isCurrent(generation), intentRevision == revision else { return }
            do {
                try configureAudioSession()
                activated = true
                break
            } catch {
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
        }
        if activated, !Task.isCancelled, recoveryGate.isCurrent(generation), intentRevision == revision {
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
                guard let self, let item, item === player.currentItem else { return }
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
            let shouldSkip = playbackRequested && transitionBackgroundTaskID != .invalid
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
        player.pause()
        player.replaceCurrentItem(with: nil)
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
            player.replaceCurrentItem(with: replacement)
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
            let shouldSkip = playbackRequested && transitionBackgroundTaskID != .invalid
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
                await handlePlaybackFailure(
                    of: item,
                    generation: recoveryGate.generation,
                    fallback: "音频播放中断"
                )
            }
        }
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
        if player.timeControlStatus == .playing {
            consecutiveAutoplayFailures = 0
            endTransitionBackgroundTask()
            state = .playing
        } else if player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
            state = .loading
        } else if player.timeControlStatus == .paused {
            if player.error != nil || item.error != nil {
                state = .failed(playbackFailureDescription(for: item, fallback: "音频播放中断"))
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
    }

    private func installWidgetNotifications() {
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
    }

    private func removeWidgetNotifications() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterRemoveEveryObserver(center, observer)
    }
}
