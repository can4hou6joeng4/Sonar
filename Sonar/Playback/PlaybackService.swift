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

/// 播放服务对离线缓存的最小依赖。具体实现由 iOS 端注入，macOS 不启用时传 nil。
@MainActor
public protocol PlaybackAudioCaching: AnyObject {
    var autoCacheEnabled: Bool { get }
    var cellularOnlyCached: Bool { get }
    func cachedURL(
        for track: Track,
        preferred: Quality,
        allowLowerQuality: Bool
    ) async -> (url: URL, quality: Quality)?
    func cacheTracks(_ tracks: [Track], quality: Quality, priorityFirst: Bool) async
    func handleNetworkChange(isExpensive: Bool) async
    func invalidateCachedAudio(for track: Track, url: URL) async
}

/// 播放服务只需要同步读取当前网络是否按流量计费。
@MainActor
public protocol PlaybackNetworkStatus: AnyObject {
    var isExpensive: Bool { get }
    var isConnected: Bool { get }
}

public extension Notification.Name {
    static let sonarNetworkStatusDidChange = Notification.Name("sonar.network.statusDidChange")
    static let sonarPlaybackDataPolicyDidChange = Notification.Name("sonar.playback.dataPolicyDidChange")
}

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
        let underlying: Error
        if case let SourceError.network(cause) = error { underlying = cause }
        else { underlying = error }
        let networkError = underlying as NSError
        if networkError.domain == NSURLErrorDomain {
            switch URLError.Code(rawValue: networkError.code) {
            case .timedOut:
                return "网络请求超时，请检查网络或 VPN 分流后重试"
            case .notConnectedToInternet:
                return "网络未连接，请联网后重试"
            case .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost, .secureConnectionFailed:
                return "无法连接音源，请检查网络或 VPN 分流后重试"
            case .networkConnectionLost, .cancelled:
                return "网络连接中断，请重试"
            default: break
            }
        }
        return sanitizedDetail(error.localizedDescription) ?? fallback
    }

    static func isNetworkFailure(_ error: Error) -> Bool {
        if case SourceError.network = error { return true }
        return (error as NSError).domain == NSURLErrorDomain
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

    /// 单曲循环不经过 loadCurrent，必须在新一轮播放前重新授予一次恢复机会，
    /// 否则第一次失败用完额度后，后续任何中断都会直接暂停。
    mutating func rearmRecovery() {
        recoveryConsumed = false
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

    /// 需要用户知道、但不应改变播放状态的成功/提示信息。
    /// RootView 监听 id 变化并用全局 Toast 呈现。
    public struct Notice: Identifiable, Equatable, Sendable {
        public let id = UUID()
        public let message: String
    }

    private static let preferredQualityKey = "preferredPlaybackQuality"
    private static let sessionKey = "sonar.playback.session"
    private static let playbackRateKey = "sonar.playback.rate"
    private static let lastPlayedQualityKey = "lastPlayedQuality"
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
    private let bufferingTimeout: Duration
    private var bufferingTimeoutTask: Task<Void, Never>?
    private var endingItem: AVPlayerItem?
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

    /// 最近一次真正拿到的音质（服务端可能降级），用于界面展示与排查。
    public private(set) var lastActualQuality: Quality?
    /// 需要提示给用户的非错误信息（例如蜂窝网络下未缓存歌曲）。
    public private(set) var notice: Notice?
    /// 当前播放项所用签名 URL 的解析时间；签名链接过期是不可恢复失败，
    /// 单曲循环必须在下一轮开始前主动换新链接。
    private var currentURLResolvedAt: Date?
    /// 缓存播放与手动导入的本地音频都无需网络。
    private var currentItemIsLocal = false
    public var isUsingCachedAudio: Bool { currentItemIsLocal && queue.current?.source != .local }
    private let audioCache: (any PlaybackAudioCaching)?
    private let networkStatus: (any PlaybackNetworkStatus)?
    private var networkObservers: [NSObjectProtocol] = []

    /// 播放速度（0.5x–2x），持久化。
    public private(set) var playbackRate: Float = 1.0

    public func setPlaybackRate(_ value: Float) {
        let clamped = min(max(value, 0.5), 2.0)
        playbackRate = clamped
        defaults.set(Double(clamped), forKey: Self.playbackRateKey)
        if state == .playing { player.rate = clamped }
    }

    private struct PersistedSession: Codable {
        let track: Track
        let elapsed: Double
        let savedAt: Date
    }

    private var lastSessionSaveAt = Date.distantPast
    private var remoteCommandTokens: [(MPRemoteCommand, Any)] = []
    private var nowPlayingArtwork: MPMediaItemArtwork?
    private var currentMediaHost: String?
    private var recoveryGate = PlaybackRecoveryGate()
    private var backgroundTransitionRevision = 0
    #if os(iOS)
    private var transitionBackgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    #endif
    // Transition intent is independent of whether iOS grants background time.
    private var isTransitionInProgress = false
    private var consecutiveAutoplayFailures = 0
    private let maxConsecutiveAutoplaySkips = 3
    private var hasPrefetchedUpcomingForCurrentTrack = false
    private struct PlaybackLocation: Sendable {
        let url: URL
        let quality: Quality?
    }

    private enum DataAccessError: Error {
        case requiresWiFi
    }

    private struct UpcomingResolution {
        let id = UUID()
        let musicID: String
        let quality: Quality
        let task: Task<PlaybackLocation, Error>
    }
    private var upcomingResolution: UpcomingResolution?
    private var activeURLResolutionTask: Task<PlaybackLocation, Error>?
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
        return AVQueuePlayer()
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
        },
        bufferingTimeout: Duration = .seconds(20),
        audioCache: (any PlaybackAudioCaching)? = nil,
        networkStatus: (any PlaybackNetworkStatus)? = nil
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
        self.bufferingTimeout = bufferingTimeout
        self.autoplaySkipDelay = autoplaySkipDelay
        self.randomIndex = randomIndex
        self.audioCache = audioCache
        self.networkStatus = networkStatus
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
        let storedRate = defaults.double(forKey: Self.playbackRateKey)
        playbackRate = storedRate > 0 ? Float(min(max(storedRate, 0.5), 2.0)) : 1.0
        queue.setShuffled(restoredMode == .shuffle)
        installTimeObserver()
        installTimeControlObserver()
        installEndObserver()
        installFailureObservers()
        installRemoteCommands()
        installWidgetNotifications()
        installAudioSessionObservers()
        installNetworkObserver()
    }

    deinit {
        MainActor.assumeIsolated {
            upcomingResolution?.task.cancel()
            activeURLResolutionTask?.cancel()
            mediaPreparationTask?.cancel()
            bufferingTimeoutTask?.cancel()
            preparedStatusObservation?.invalidate()
            preparedBufferObservation?.invalidate()
            endTransitionBackgroundTask()
            removeWidgetNotifications()
            for observer in networkObservers { NotificationCenter.default.removeObserver(observer) }
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
        guard let selection = PlaybackQueue.playableSelection(tracks, startingAt: index) else { return }
        let tracks = selection.tracks
        let index = selection.index
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
        guard let selection = PlaybackQueue.playableSelection(tracks, startingAt: index) else { return false }
        let tracks = selection.tracks
        let index = selection.index
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
        guard track.source.isEnabled else { return }
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
        guard track.source.isEnabled else { return false }
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
        guard track.source.isEnabled else { return }
        guard let currentIndex = queue.currentIndex else {
            _ = await enqueue(track)
            return
        }
        queue.insert(track, at: currentIndex + 1)
        prefetchUpcomingTrackIfNeeded()
    }

    public func play() async {
        cancelBufferingTimeout()
        intentRevision += 1
        shouldResumeAfterInterruption = false
        consecutiveAutoplayFailures = 0
        playbackRequested = true
        let needsLocalItem = requiresLocalPlayback && !currentItemIsLocal
            && queue.current?.source != .local
        if player.currentItem == nil || player.currentItem?.status == .failed || needsLocalItem {
            await loadCurrent(
                autoplay: true,
                refreshing: player.currentItem?.status == .failed,
                resumeAt: elapsed
            )
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
        persistSession(force: true)
        intentRevision += 1
        shouldResumeAfterInterruption = false
        playbackRequested = false
        cancelBufferingTimeout()
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
        #if os(iOS)
        updateWidgetSnapshot(for: queue.current)
        #endif
        prefetchUpcomingTrackIfNeeded()
    }

    /// 记录当前曲目与进度，冷启动时恢复（不自动播放）。
    private func persistSession(force: Bool = false) {
        guard let track = queue.current else { return }
        let now = Date()
        guard force || now.timeIntervalSince(lastSessionSaveAt) > 5 else { return }
        lastSessionSaveAt = now
        let session = PersistedSession(track: track, elapsed: max(0, elapsed), savedAt: now)
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: Self.sessionKey)
    }

    /// 冷启动恢复上次播放的曲目与进度，保持暂停态，由用户决定继续播放。
    public func restoreLastSessionIfNeeded() async {
        guard queue.current == nil,
              let data = defaults.data(forKey: Self.sessionKey),
              let session = try? JSONDecoder().decode(PersistedSession.self, from: data) else { return }
        guard session.track.source.isEnabled, session.track.isPlayable else { return }
        guard Date().timeIntervalSince(session.savedAt) < 7 * 24 * 60 * 60 else { return }
        await replaceQueue([session.track], autoplay: false)
        if session.elapsed > 1, duration > 0 {
            await seek(to: min(session.elapsed, max(0, duration - 1)))
        }
        state = .paused
    }

    public func seek(to seconds: TimeInterval) async {
        let generation = recoveryGate.generation
        let item = player.currentItem
        let target = CMTime(seconds: max(0, min(seconds, duration)), preferredTimescale: 600)
        guard item != nil else {
            elapsed = target.seconds
            updateNowPlaying()
            return
        }
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
        guard track.source.isEnabled else { return }
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
        guard item === player.currentItem, playbackRequested, endingItem !== item else { return }
        endingItem = item
        cancelBufferingTimeout()
        await finishPlaybackEnd(of: item, generation: recoveryGate.generation, revision: intentRevision)
    }

    private func finishPlaybackEnd(of item: AVPlayerItem, generation: Int, revision: Int) async {
        defer { if endingItem === item { endingItem = nil } }
        guard item === player.currentItem, playbackRequested,
              recoveryGate.isCurrent(generation), intentRevision == revision else { return }
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

    private var isExpensiveNetwork: Bool { networkStatus?.isExpensive ?? false }
    private var cellularOnlyCached: Bool { audioCache?.cellularOnlyCached ?? false }
    private var unmeteredNetworkAvailable: Bool {
        (networkStatus?.isConnected ?? true) && !isExpensiveNetwork
    }
    private var requiresLocalPlayback: Bool { cellularOnlyCached && !unmeteredNetworkAvailable }

    private func resolvePlaybackLocation(
        for track: Track,
        quality: Quality,
        refreshing: Bool = false,
        prefetched: UpcomingResolution? = nil
    ) async throws -> PlaybackLocation {
        try Task.checkCancellation()
        try resolver.requirePlaybackSupport(for: track.source)
        let cached = await audioCache?.cachedURL(
            for: track,
            preferred: quality,
            allowLowerQuality: !unmeteredNetworkAvailable
        )
        try Task.checkCancellation()
        if let cached {
            prefetched?.task.cancel()
            return PlaybackLocation(url: cached.url, quality: cached.quality)
        }
        guard track.source == .local || !requiresLocalPlayback else {
            throw DataAccessError.requiresWiFi
        }
        if let prefetched {
            do {
                return try await withTaskCancellationHandler {
                    let location = try await prefetched.task.value
                    try Task.checkCancellation()
                    guard location.url.isFileURL || !requiresLocalPlayback else {
                        throw DataAccessError.requiresWiFi
                    }
                    return location
                } onCancel: {
                    prefetched.task.cancel()
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch is DataAccessError {
                throw DataAccessError.requiresWiFi
            } catch {
                try Task.checkCancellation()
            }
        }
        let resolved = try await resolver.resolvedMusicURL(for: track, quality: quality, refreshing: refreshing)
        try Task.checkCancellation()
        guard resolved.url.isFileURL || !requiresLocalPlayback else { throw DataAccessError.requiresWiFi }
        return PlaybackLocation(url: resolved.url, quality: track.source == .local ? nil : resolved.quality)
    }

    private func makePlaybackItem(url: URL, bufferDuration: TimeInterval = 10) -> AVPlayerItem {
        var options: [String: Any] = [:]
        if !url.isFileURL, cellularOnlyCached {
            options[AVURLAssetAllowsCellularAccessKey] = false
            options[AVURLAssetAllowsExpensiveNetworkAccessKey] = false
        }
        let item = AVPlayerItem(asset: AVURLAsset(url: url, options: options))
        if !url.isFileURL { item.preferredForwardBufferDuration = bufferDuration }
        return item
    }

    /// Wi-Fi 下把当前曲目与队列后 3 首交给缓存服务。重复调用由缓存端去重。
    private func scheduleCacheDownloads() {
        guard let audioCache,
              let current = queue.current,
              playbackRequested,
              unmeteredNetworkAvailable,
              audioCache.autoCacheEnabled else { return }
        let tracks = [current] + (playbackMode == .repeatOne ? [] : queue.upcoming(
            limit: 3,
            wrapping: playbackMode != .playInOrder
        ))
        let quality = preferredQuality
        Task { [audioCache, tracks, quality] in
            await audioCache.cacheTracks(tracks, quality: quality, priorityFirst: true)
        }
    }

    private func installNetworkObserver() {
        guard networkStatus != nil else { return }
        let names: [Notification.Name] = [
            .sonarNetworkStatusDidChange,
            .sonarPlaybackDataPolicyDidChange,
        ]
        for name in names {
            networkObservers.append(
                NotificationCenter.default.addObserver(
                    forName: name,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        await self?.handleNetworkStatusChange()
                    }
                }
            )
        }
    }

    private func handleNetworkStatusChange() async {
        guard networkStatus != nil else { return }
        if let audioCache {
            Task { await audioCache.handleNetworkChange(isExpensive: !unmeteredNetworkAvailable) }
        }
        guard requiresLocalPlayback else {
            scheduleCacheDownloads()
            return
        }
        // 无论当前是否暂停，都移除下一首的网络缓冲项。
        discardUpcoming()
        guard !currentItemIsLocal, let track = queue.current, track.source != .local else { return }
        let resumeAt = currentPosition()
        let wasRequested = playbackRequested
        _ = recoveryGate.beginLoad()
        activeURLResolutionTask?.cancel()
        activeURLResolutionTask = nil
        itemStatusObservation?.invalidate()
        player.pause()
        replacePlayerItem(with: nil)
        elapsed = resumeAt
        // 先拆除网络资源，再查询缓存；已完成的缓存可以接着播放。
        await loadCurrent(autoplay: wasRequested, resumeAt: resumeAt)
    }

    private func currentPosition() -> TimeInterval {
        let position = player.currentItem?.currentTime().seconds ?? elapsed
        return position.isFinite ? max(elapsed, position) : elapsed
    }

    /// 蜂窝网络下没有缓存可用时统一走这里：停掉网络播放，但保留曲目与进度。
    private func handleCellularPlaybackBlocked() {
        _ = recoveryGate.beginLoad()
        activeURLResolutionTask?.cancel()
        activeURLResolutionTask = nil
        discardUpcoming()
        cancelBufferingTimeout()
        intentRevision += 1
        playbackRequested = false
        shouldResumeAfterInterruption = false
        player.pause()
        replacePlayerItem(with: nil)
        currentItemIsLocal = false
        currentURLResolvedAt = nil
        currentMediaHost = nil
        state = .paused
        updateNowPlaying()
        endTransitionBackgroundTask()
        postNotice("蜂窝网络下仅播放已缓存歌曲，请在 Wi-Fi 下播放以自动缓存")
    }

    private func postNotice(_ message: String) {
        notice = Notice(message: message)
    }

    public func setPreferredQuality(_ quality: Quality) async -> QualityChange {
        guard preferredQuality != quality else { return .unchanged }
        preferredQuality = quality
        discardUpcoming()
        activeURLResolutionTask?.cancel()
        activeURLResolutionTask = nil
        guard let track = queue.current else { return .deferred }
        let generation = recoveryGate.beginLoad()
        cancelBufferingTimeout()

        let resumeAt = elapsed
        let previousState = state
        let revision = intentRevision
        state = .loading
        let resolutionTask = Task { try await resolvePlaybackLocation(for: track, quality: quality) }
        activeURLResolutionTask = resolutionTask
        defer {
            if recoveryGate.isCurrent(generation) { activeURLResolutionTask = nil }
        }
        do {
            let location = try await withTaskCancellationHandler {
                try await resolutionTask.value
            } onCancel: {
                resolutionTask.cancel()
            }
            try Task.checkCancellation()
            guard recoveryGate.isCurrent(generation), queue.current?.musicID == track.musicID else {
                return .deferred
            }
            try completeCurrentLoad(
                item: makePlaybackItem(url: location.url),
                url: location.url,
                generation: generation,
                prepared: false,
                actualQuality: location.quality,
                resumeAt: resumeAt
            )
            return .reloaded(location.quality ?? quality)
        } catch {
            guard recoveryGate.isCurrent(generation), queue.current?.musicID == track.musicID else {
                return .deferred
            }
            state = intentRevision == revision ? previousState : (playbackRequested ? .loading : .paused)
            if let item = player.currentItem { observeStatus(of: item, generation: generation) }
            synchronizePlaybackState()
            updateNowPlaying()
            if error is DataAccessError {
                postNotice("蜂窝网络下仅播放已缓存歌曲，音质偏好将在 Wi-Fi 下生效")
                return .deferred
            }
            if error is CancellationError || (error as? URLError)?.code == .cancelled || Task.isCancelled { return .deferred }
            return .failed(
                PlaybackFailureDiagnostics.message(for: error, fallback: "无法切换音质")
            )
        }
    }

    private func loadCurrent(
        autoplay: Bool,
        refreshing: Bool = false,
        resumeAt: TimeInterval = 0
    ) async {
        PerfLog.mark("load_start", refreshing ? "refresh" : "normal")
        cancelBufferingTimeout()
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
        elapsed = resumeAt
        duration = track.durationSeconds ?? 0
        state = .loading
        hasPrefetchedUpcomingForCurrentTrack = false
        updateNowPlaying()
        let resolutionTask = Task {
            try await resolvePlaybackLocation(
                for: track,
                quality: quality,
                refreshing: refreshing,
                prefetched: prefetched
            )
        }
        activeURLResolutionTask = resolutionTask
        defer {
            if recoveryGate.isCurrent(generation) { activeURLResolutionTask = nil }
        }
        do {
            let location = try await withTaskCancellationHandler {
                try await resolutionTask.value
            } onCancel: {
                resolutionTask.cancel()
            }
            try Task.checkCancellation()
            guard recoveryGate.isCurrent(generation), queue.current?.musicID == track.musicID else { return }
            let canReusePrepared = preparedItem.flatMap { item -> AVPlayerItem? in
                guard let asset = item.asset as? AVURLAsset, asset.url == location.url,
                      item.status != .failed,
                      let queuePlayer = player as? AVQueuePlayer,
                      queuePlayer.items().dropFirst().first === item else { return nil }
                return item
            }
            try completeCurrentLoad(
                item: canReusePrepared ?? makePlaybackItem(url: location.url),
                url: location.url,
                generation: generation,
                prepared: canReusePrepared != nil,
                actualQuality: location.quality,
                resumeAt: resumeAt
            )
        } catch is DataAccessError {
            guard recoveryGate.isCurrent(generation), queue.current?.musicID == track.musicID else { return }
            handleCellularPlaybackBlocked()
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
                && !PlaybackFailureDiagnostics.isNetworkFailure(error)
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

    private func completeCurrentLoad(
        item: AVPlayerItem,
        url: URL,
        generation: Int,
        prepared: Bool,
        actualQuality: Quality? = nil,
        resumeAt: TimeInterval = 0
    ) throws {
        guard url.isFileURL || !requiresLocalPlayback else { throw DataAccessError.requiresWiFi }
        let isLocal = url.isFileURL
        PerfLog.mark(isLocal ? "cache_hit" : "url_ready", queue.current?.musicID ?? "")
        currentItemIsLocal = isLocal
        if isLocal {
            currentURLResolvedAt = nil
            currentMediaHost = nil
        } else {
            currentURLResolvedAt = Date()
            currentMediaHost = url.host
        }
        if let actualQuality {
            lastActualQuality = actualQuality
            defaults.set(actualQuality.rawValue, forKey: Self.lastPlayedQualityKey)
        }
        measuredItem = item
        lastTransitionTiming?.reusedPreparedItem = prepared
        recordTransitionStage("resolved")
        if prepared, let queuePlayer = player as? AVQueuePlayer {
            queuePlayer.advanceToNextItem()
        } else {
            replacePlayerItem(with: item)
        }
        observeStatus(of: item, generation: generation)
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
        if item == nil {
            currentItemIsLocal = false
            currentURLResolvedAt = nil
            currentMediaHost = nil
        }
        if let queuePlayer = player as? AVQueuePlayer {
            queuePlayer.removeAllItems()
            if let item { queuePlayer.insert(item, after: nil) }
        } else {
            player.replaceCurrentItem(with: item)
        }
    }

    private func prefetchUpcomingTrackIfNeeded() {
        defer { scheduleCacheDownloads() }
        guard playbackMode != .repeatOne,
              let nextTrack = queue.peekNext(wrapping: playbackMode != .playInOrder),
              nextTrack.source.isEnabled,
              nextTrack.musicID != queue.current?.musicID else {
            discardUpcoming()
            return
        }
        // 蜂窝或断网时不做音频预缓冲，切歌时直接查询本地缓存。
        guard unmeteredNetworkAvailable else {
            discardUpcoming()
            return
        }
        let quality = preferredQuality
        if upcomingResolution?.musicID == nextTrack.musicID, upcomingResolution?.quality == quality { return }
        discardUpcoming()
        guard playbackRequested, player.currentItem != nil else { return }
        let task = Task { try await resolvePlaybackLocation(for: nextTrack, quality: quality) }
        let request = UpcomingResolution(musicID: nextTrack.musicID, quality: quality, task: task)
        upcomingResolution = request
        guard player is AVQueuePlayer else { return }
        mediaPreparationTask = Task { [weak self] in
            do {
                let location = try await task.value
                try Task.checkCancellation()
                guard let self, self.upcomingResolution?.id == request.id,
                      self.unmeteredNetworkAvailable,
                      let queuePlayer = self.player as? AVQueuePlayer,
                      let currentItem = queuePlayer.currentItem else { return }
                let item = self.makePlaybackItem(url: location.url, bufferDuration: 5)
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
        isTransitionInProgress = true
        #if os(iOS)
        let revision = backgroundTransitionRevision
        transitionBackgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "sonar-track-transition") { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.backgroundTransitionRevision == revision else { return }
                self.handleTransitionBackgroundExpiration()
            }
        }
        #endif
    }

    private func endTransitionBackgroundTask() {
        backgroundTransitionRevision += 1
        #if os(iOS)
        if transitionBackgroundTaskID != .invalid {
            UIApplication.shared.endBackgroundTask(transitionBackgroundTaskID)
            transitionBackgroundTaskID = .invalid
        }
        #endif
        isTransitionInProgress = false
    }

    func handleTransitionBackgroundExpiration() {
        if isTransitionInProgress, playbackRequested, state == .loading {
            // A pending lookup/recovery must not install an item after iOS
            // withdraws background time or leave the UI loading on return.
            _ = recoveryGate.beginLoad()
            cancelBufferingTimeout()
            activeURLResolutionTask?.cancel()
            activeURLResolutionTask = nil
            discardUpcoming()
            playbackRequested = false
            player.pause()
            state = .failed("后台加载超时，请检查网络或 VPN 分流后重试")
            updateNowPlaying()
        }
        endTransitionBackgroundTask()
    }

    private func restartCurrent() async {
        // 签名链接通常在 20 分钟内有效；单曲循环若沿用同一链接，
        // 后者会在某一轮中途失效，表现为自动暂停并提示重试。
        if shouldRefreshCurrentURLBeforeRestart() {
            await loadCurrent(autoplay: true, refreshing: true)
            endTransitionBackgroundTask()
            return
        }
        let generation = recoveryGate.generation
        let revision = intentRevision
        recoveryGate.rearmRecovery()
        await player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        guard !Task.isCancelled, recoveryGate.isCurrent(generation), intentRevision == revision else { return }
        elapsed = 0
        await play()
        endTransitionBackgroundTask()
    }

    /// 下一轮播放结束前链接就会过期时，提前重新解析，避免循环中途中断。
    private func shouldRefreshCurrentURLBeforeRestart() -> Bool {
        guard let resolvedAt = currentURLResolvedAt else { return false }
        let age = Date().timeIntervalSince(resolvedAt)
        let remaining = max(duration, queue.current?.durationSeconds ?? 0)
        // 17 分钟阈值给 20 分钟签名留 3 分钟余量。
        return age + remaining > 17 * 60
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
            cancelBufferingTimeout()
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
            cancelBufferingTimeout()
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
        if requiresLocalPlayback, !currentItemIsLocal, queue.current?.source != .local {
            await play()
        } else if let currentItem = player.currentItem, currentItem.status == .readyToPlay {
            state = .playing
            player.playImmediately(atRate: 1.0)
            synchronizePlaybackState()
            updateNowPlaying()
        } else {
            await play()
        }
    }

    private func installTimeObserver() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let item = self.player.currentItem else { return }
                // A queued tick may belong to the item we just replaced.
                let seconds = item.currentTime().seconds
                if seconds.isFinite { self.elapsed = max(0, seconds) }
                self.persistSession()
                self.synchronizePlaybackState()
                let itemDuration = item.duration.seconds
                if itemDuration.isFinite, itemDuration > 0 {
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
                    PerfLog.mark("item_ready")
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
        fallback: String,
        allowsAutoplaySkip: Bool = true
    ) async {
        guard item === player.currentItem,
              recoveryGate.isCurrent(generation),
              endingItem !== item,
              let track = queue.current else { return }
        if playbackRequested, hasReachedMediaEnd(item) {
            await handlePlaybackEnded(of: item)
            return
        }
        cancelBufferingTimeout()
        guard recoveryGate.consumeRecovery(for: generation) else {
            let shouldSkip = playbackRequested && isTransitionInProgress && allowsAutoplaySkip
            let revision = intentRevision
            playbackRequested = false
            player.pause()
            let description = playbackFailureDescription(for: item, fallback: fallback)
            PerfLog.mark("playback_failed", "\(queue.current?.musicID ?? "")|\(description)")
            logger.error("playback_failed \(description, privacy: .public)")
            state = .failed(description)
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
        // The periodic UI progress can lag, especially while backgrounded.
        // Capture the item's position before removing it so recovery cannot rewind.
        let position = item.currentTime().seconds
        let resumeAt = position.isFinite ? max(elapsed, position) : elapsed
        let failedCacheURL = (item.asset as? AVURLAsset)?.url
        state = .loading
        discardUpcoming()
        player.pause()
        replacePlayerItem(with: nil)
        currentMediaHost = nil
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        elapsed = resumeAt
        updateNowPlaying()
        if let failedCacheURL, failedCacheURL.isFileURL, track.source != .local {
            await audioCache?.invalidateCachedAudio(for: track, url: failedCacheURL)
        }

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

        let resolutionTask = Task {
            try await resolvePlaybackLocation(for: track, quality: preferredQuality, refreshing: true)
        }
        activeURLResolutionTask = resolutionTask
        defer {
            if recoveryGate.isCurrent(generation) { activeURLResolutionTask = nil }
        }
        do {
            let location = try await withTaskCancellationHandler {
                try await resolutionTask.value
            } onCancel: {
                resolutionTask.cancel()
            }
            try Task.checkCancellation()
            guard recoveryGate.isCurrent(generation),
                  queue.currentIndex == queueIndex,
                  queue.current?.musicID == trackID else { return }
            try completeCurrentLoad(
                item: makePlaybackItem(url: location.url),
                url: location.url,
                generation: generation,
                prepared: false,
                actualQuality: location.quality,
                resumeAt: resumeAt
            )
        } catch is DataAccessError {
            guard recoveryGate.isCurrent(generation), queue.current?.musicID == trackID else { return }
            handleCellularPlaybackBlocked()
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
            let shouldSkip = playbackRequested && isTransitionInProgress && allowsAutoplaySkip
                && !PlaybackFailureDiagnostics.isNetworkFailure(error)
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
                      let item = notification.object as? AVPlayerItem,
                      item === player.currentItem, endingItem !== item,
                      playbackRequested else { return }
                if case .failed = state { return }
                if shouldResumeAfterInterruption { return }
                state = .loading
                startBufferingTimeoutIfNeeded()
                updateNowPlaying()
            }
        }

        failedToEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self, let item = notification.object as? AVPlayerItem,
                      item === player.currentItem, endingItem !== item else { return }
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
        guard queue.current != nil, let item = player.currentItem else {
            cancelBufferingTimeout()
            return
        }
        if endingItem === item { cancelBufferingTimeout(); return }
        if case .failed = state { cancelBufferingTimeout(); return }
        if item.status == .failed {
            // 失败由 observeStatus / handlePlaybackFailure 负责处理，避免将失败状态覆写为 loading
            return
        }
        guard playbackRequested else {
            cancelBufferingTimeout()
            state = .paused
            return
        }
        // Use the real item's duration, never catalog metadata. This also
        // recovers an end notification missed while the app changed state.
        if player.timeControlStatus == .paused, item.status == .readyToPlay,
           hasReachedMediaEnd(item) {
            schedulePlaybackEnd(of: item)
            return
        }
        if player.timeControlStatus == .playing, item.status == .readyToPlay {
            cancelBufferingTimeout()
            if item === measuredItem {
                recordTransitionStage("ready")
                recordTransitionStage("playing")
            }
            consecutiveAutoplayFailures = 0
            endTransitionBackgroundTask()
            state = .playing
            if player.rate != playbackRate { player.rate = playbackRate }
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
        if state == .loading { startBufferingTimeoutIfNeeded() }
        else { cancelBufferingTimeout() }
    }

    private func cancelBufferingTimeout() {
        bufferingTimeoutTask?.cancel()
        bufferingTimeoutTask = nil
    }

    private func startBufferingTimeoutIfNeeded() {
        guard bufferingTimeoutTask == nil, playbackRequested, !shouldResumeAfterInterruption,
              let item = player.currentItem else { return }
        let generation = recoveryGate.generation
        let revision = intentRevision
        let timeout = bufferingTimeout
        bufferingTimeoutTask = Task { [weak self, weak item] in
            do { try await Task.sleep(for: timeout) }
            catch { return }
            guard let self, let item, !Task.isCancelled,
                  self.recoveryGate.isCurrent(generation), self.intentRevision == revision,
                  self.player.currentItem === item, self.playbackRequested,
                  !self.shouldResumeAfterInterruption, self.state == .loading else { return }
            self.bufferingTimeoutTask = nil
            await self.handlePlaybackFailure(
                of: item, generation: generation,
                fallback: "音频加载超时，请检查网络或 VPN 分流后重试",
                allowsAutoplaySkip: false
            )
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
            MainActor.assumeIsolated {
                guard let item = notification.object as? AVPlayerItem else { return }
                self?.schedulePlaybackEnd(of: item)
            }
        }
    }

    private func hasReachedMediaEnd(_ item: AVPlayerItem) -> Bool {
        let mediaDuration = item.duration.seconds
        let position = item.currentTime().seconds
        return mediaDuration.isFinite && mediaDuration > 0 && position.isFinite
            && position >= mediaDuration - 0.02
    }

    private func schedulePlaybackEnd(of item: AVPlayerItem) {
        guard item === player.currentItem, playbackRequested, endingItem !== item else { return }
        // Claim completion synchronously. A queued failure or timeout must not
        // replace this finished item before the transition task gets to run.
        endingItem = item
        cancelBufferingTimeout()
        // Acquire background time inside the notification callback, before the
        // async hop can let iOS suspend an app whose audio has just stopped.
        beginTransitionBackgroundTask()
        let generation = recoveryGate.generation
        let revision = intentRevision
        Task { [weak self] in
            await self?.finishPlaybackEnd(of: item, generation: generation, revision: revision)
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
                isShuffleOn: playbackMode == .shuffle,
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
            isShuffleOn: playbackMode == .shuffle,
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
            "cn.bobochang.sonar.remote.pause",
            WidgetShareStore.DarwinNotification.toggleShuffle
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
                        case WidgetShareStore.DarwinNotification.toggleShuffle:
                            let mode: PlaybackMode = service.playbackMode == .shuffle ? .sequence : .shuffle
                            service.setPlaybackMode(mode)
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
