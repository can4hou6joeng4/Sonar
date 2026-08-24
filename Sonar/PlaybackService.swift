import AVFoundation
import Foundation
import MediaPlayer
import Observation
import UIKit

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

    public enum PlaybackMode: Int, CaseIterable, Sendable {
        case sequence
        case shuffle
        case repeatOne
    }

    /// 切换音质的结果。界面据此给出不同提示，不允许「点了没反应」。
    public enum QualityChange: Equatable, Sendable {
        case unchanged
        case reloaded(Quality)
        case deferred
        case failed(String)
    }

    private static let preferredQualityKey = "preferredPlaybackQuality"

    public private(set) var queue = PlaybackQueue()
    public private(set) var state: State = .idle
    public private(set) var playbackMode: PlaybackMode = .sequence
    public private(set) var elapsed: TimeInterval = 0
    public private(set) var duration: TimeInterval = 0
    /// 用户选定的音质**上限**：解析器从这一档起逐级下降，所以它是起点而不是锁死值。
    public private(set) var preferredQuality: Quality {
        didSet { defaults.set(preferredQuality.rawValue, forKey: Self.preferredQualityKey) }
    }
    private let player: AVPlayer
    private let resolver: PlaybackURLResolving
    private let defaults: UserDefaults
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var remoteCommandTokens: [(MPRemoteCommand, Any)] = []
    private var nowPlayingArtwork: MPMediaItemArtwork?

    public init(
        player: AVPlayer = AVPlayer(),
        resolver: PlaybackURLResolving = PlaybackURLResolver(),
        defaults: UserDefaults = .standard
    ) {
        self.player = player
        self.resolver = resolver
        self.defaults = defaults
        preferredQuality = defaults.string(forKey: Self.preferredQualityKey)
            .flatMap(Quality.init(rawValue:)) ?? .hiRes
        installTimeObserver()
        installEndObserver()
        installRemoteCommands()
    }

    deinit {
        MainActor.assumeIsolated {
            if let timeObserver { player.removeTimeObserver(timeObserver) }
            if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
            for (command, token) in remoteCommandTokens { command.removeTarget(token) }
        }
    }

    public func replaceQueue(_ tracks: [Track], startingAt index: Int = 0, autoplay: Bool = true) async {
        queue.replace(with: tracks, startingAt: index)
        await loadCurrent(autoplay: autoplay)
    }

    public func play() async {
        if player.currentItem == nil {
            await loadCurrent(autoplay: true)
            return
        }
        do {
            try configureAudioSession()
            player.play()
            state = .playing
            updateNowPlaying()
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func pause() {
        player.pause()
        state = .paused
        updateNowPlaying()
    }

    public func togglePlayback() async {
        if state == .playing { pause() } else { await play() }
    }

    public func setPlaybackMode(_ mode: PlaybackMode) {
        playbackMode = mode
    }

    public func seek(to seconds: TimeInterval) async {
        let target = CMTime(seconds: max(0, min(seconds, duration)), preferredTimescale: 600)
        await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        elapsed = target.seconds
        updateNowPlaying()
    }

    public func next() async {
        guard queue.advance() != nil else { return }
        await loadCurrent(autoplay: true)
    }

    public func previous() async {
        if elapsed > 3 {
            await seek(to: 0)
            return
        }
        guard queue.retreat() != nil else {
            await seek(to: 0)
            return
        }
        await loadCurrent(autoplay: true)
    }

    public func selectQueueItem(at index: Int) async {
        guard queue.tracks.indices.contains(index), queue.currentIndex != index else { return }
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
        if removedCurrent { await loadCurrent(autoplay: state == .playing) }
    }

    public func clearUpcoming() {
        queue.clearUpcoming()
    }

    func handlePlaybackEnded() async {
        guard let currentIndex = queue.currentIndex else { return }

        switch playbackMode {
        case .sequence:
            guard queue.advance() != nil else {
                pause()
                return
            }
            await loadCurrent(autoplay: true)
        case .shuffle:
            guard queue.tracks.count > 1 else {
                await restartCurrent()
                return
            }
            let offset = Int.random(in: 1..<queue.tracks.count)
            queue.select(index: (currentIndex + offset) % queue.tracks.count)
            await loadCurrent(autoplay: true)
        case .repeatOne:
            await restartCurrent()
        }
    }

    public func updateNowPlayingArtwork(_ image: UIImage?) {
        nowPlayingArtwork = image.map { image in
            MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        updateNowPlaying()
    }

    /// 记下新的音质上限，并让当前曲目按它重新解析。
    /// 解析成功前不碰 `AVPlayer`，失败时旧的流还在播，只回滚状态并把原因交回界面。
    @discardableResult
    public func setPreferredQuality(_ quality: Quality) async -> QualityChange {
        guard preferredQuality != quality else { return .unchanged }
        preferredQuality = quality
        guard let track = queue.current else { return .deferred }

        let resumeAt = elapsed
        let previousState = state
        let wasPlaying = previousState == .playing
        state = .loading
        do {
            let url = try await resolver.musicURL(for: track, quality: quality)
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            if resumeAt > 0 {
                // 用回调版而不是 await 版：新 item 还没 ready 时 await 会一直挂着，
                // 而我们只需要把起播点排进队列。
                player.seek(to: CMTime(seconds: resumeAt, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { _ in }
                elapsed = resumeAt
            } else {
                elapsed = 0
            }
            if wasPlaying {
                try configureAudioSession()
                player.play()
                state = .playing
            } else {
                state = .paused
            }
            updateNowPlaying()
            return .reloaded(quality)
        } catch {
            state = previousState
            updateNowPlaying()
            return .failed(error.localizedDescription)
        }
    }

    private func loadCurrent(autoplay: Bool) async {
        guard let track = queue.current else {
            player.replaceCurrentItem(with: nil)
            elapsed = 0
            duration = 0
            state = .idle
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        state = .loading
        do {
            let url = try await resolver.musicURL(for: track, quality: preferredQuality)
            let item = AVPlayerItem(url: url)
            player.replaceCurrentItem(with: item)
            elapsed = 0
            duration = track.durationSeconds ?? 0
            updateNowPlaying()
            if autoplay {
                try configureAudioSession()
                player.play()
                state = .playing
            } else {
                state = .paused
            }
            updateNowPlaying()
        } catch {
            state = .failed(error.localizedDescription)
            updateNowPlaying()
        }
    }

    private func restartCurrent() async {
        await player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        elapsed = 0
        await play()
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true)
    }

    private func installTimeObserver() {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.elapsed = time.seconds.isFinite ? max(0, time.seconds) : 0
                if let itemDuration = self.player.currentItem?.duration.seconds, itemDuration.isFinite, itemDuration > 0 {
                    self.duration = itemDuration
                }
                self.updateNowPlaying()
            }
        }
    }

    private func installEndObserver() {
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil, queue: .main) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self, notification.object as? AVPlayerItem === player.currentItem else { return }
                await handlePlaybackEnded()
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

    private func updateNowPlaying() {
        guard let track = queue.current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
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
    }
}

extension Track {
    var durationSeconds: TimeInterval? {
        guard let interval else { return nil }
        let components = interval.split(separator: ":").compactMap { Double($0) }
        guard !components.isEmpty else { return nil }
        return components.reversed().enumerated().reduce(0) { result, item in
            result + item.element * pow(60, Double(item.offset))
        }
    }
}
