import AppKit
import Observation
import SwiftData
import UniformTypeIdentifiers

/// Process-owned services. Every window and the notch use this same player and store.
@MainActor @Observable
final class MacAppModel {
    let runtime: SourceRuntime
    let playback: PlaybackService
    let artworkService: ArtworkService?
    private(set) var library: LibraryStore?
    private(set) var libraryTracks: [Track] = []
    private(set) var recentTracks: [Track] = []
    private(set) var lyrics: LyricsDocument?
    private(set) var artwork: NSImage?
    private(set) var libraryFailed = false
    var errorMessage: String?
    var notice: String?
    var playbackActionTitle: String {
        if playback.state == .loading && playback.playbackRequested { return "取消加载" }
        if case .failed = playback.state { return "重试播放" }
        return playback.playbackRequested ? "暂停" : "播放"
    }
    var notchEnabled: Bool {
        didSet {
            UserDefaults.standard.set(notchEnabled, forKey: "macNotchEnabled")
            notchController?.setEnabled(notchEnabled)
        }
    }
    @ObservationIgnored private var container: ModelContainer?
    @ObservationIgnored private var notchController: NotchWindowController?
    @ObservationIgnored private var detailTask: Task<Void, Never>?
    @ObservationIgnored private let detailRefresh: TrackDetailRefreshCoordinator
    @ObservationIgnored private var observedTrackID: String?
    @ObservationIgnored private var recordedTrackID: String?

    static var storeURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("cn.bobochang.sonar.mac", isDirectory: true)
            .appendingPathComponent("Sonar.store")
    }

    init() {
        let credentials = BuildCredentialStore()
        let breaker = ChkszCircuitBreaker()
        let api = ChkszAPIClient(credentials: credentials, breaker: breaker)
        let netease = ChkszNetEaseClient(api: api)
        let runtime = FallbackSourceRuntime(primary: JavaScriptSourceRuntime(), neteaseFallback: netease)
        self.runtime = runtime
        playback = PlaybackService(resolver: PlaybackResolverPipeline.make(
            primary: PlaybackURLResolver(credentials: credentials, breaker: breaker, chkszAPI: api, wyFallback: netease),
            sourceRuntime: runtime
        ))
        artworkService = try? ArtworkService(sourceRuntime: runtime,
            cacheDirectory: URL.cachesDirectory.appendingPathComponent("cn.bobochang.sonar.mac/Artwork"))
        detailRefresh = TrackDetailRefreshCoordinator(sourceRuntime: runtime)
        notchEnabled = UserDefaults.standard.object(forKey: "macNotchEnabled") as? Bool ?? true
        retryLibrary()
        observePlayback()
    }

    func start() {
        guard notchController == nil else { return }
        notchController = NotchWindowController(model: self)
        notchController?.setEnabled(notchEnabled)
    }

    func retryLibrary() {
        guard container == nil else { return }
        do {
            try FileManager.default.createDirectory(at: Self.storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let container = try SonarModelContainer.make(url: Self.storeURL)
            self.container = container
            library = LibraryStore(container: container)
            libraryFailed = false
            reloadLibrary()
        } catch {
            libraryFailed = true
        }
    }

    func reloadLibrary() {
        guard let library else { return }
        do {
            libraryTracks = try library.ensurePersonalPlaylist().orderedItems.compactMap { $0.track.track }
            recentTracks = try library.recentTracks()
        } catch { errorMessage = "无法读取资料库，请重试。原有资料仍然保留。" }
    }

    func play(_ tracks: [Track], at index: Int = 0) async {
        guard tracks.indices.contains(index) else { return }
        await playback.replaceQueue(tracks, startingAt: index)
    }

    func playFavorites(at index: Int = 0) async {
        guard let library, libraryTracks.indices.contains(index) else { return }
        do {
            let playlist = try library.ensurePersonalPlaylist()
            await playback.replaceQueue(libraryTracks, startingAt: index, activePlaylistID: playlist.id)
        } catch { errorMessage = "无法打开个人歌单，请重试。" }
    }

    func collect(_ track: Track) {
        guard let library else { return }
        do {
            let result = try library.collect(track)
            playback.onTrackAddedToPlaylist(track, playlistID: result.playlist.id)
            reloadLibrary()
            notice = result.inserted ? "已加入个人歌单" : "这首歌已在个人歌单中"
        } catch { errorMessage = "收藏未保存，请重试。" }
    }

    func removeFavorite(_ track: Track) {
        guard let library else { return }
        do {
            let playlist = try library.ensurePersonalPlaylist()
            guard let index = playlist.orderedItems.firstIndex(where: { $0.track.musicId == track.musicID }) else { return }
            try library.removeItem(at: index, from: playlist)
            playback.onTrackRemovedFromPlaylist(track, playlistID: playlist.id)
            reloadLibrary()
        } catch { errorMessage = "未能从歌单移除，请重试。" }
    }

    func importBackup() {
        guard let library else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "导入 Sonar 歌单备份，已有歌曲会自动去重。"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                do {
                    let result = try library.importPersonalPlaylist(from: Data(contentsOf: url))
                    self?.reloadLibrary()
                    self?.notice = "已导入 \(result.insertedCount) 首歌曲，跳过 \(result.skippedCount) 首重复歌曲"
                } catch { self?.errorMessage = "导入失败：\(error.localizedDescription)" }
            }
        }
    }

    func exportBackup() {
        do {
            guard let data = try library?.exportPersonalPlaylist() else { return }
            save(data, name: "Sonar-歌单.json", successMessage: "歌单备份已导出")
        } catch { errorMessage = "导出失败，请重试。" }
    }

    func exportRecovery() {
        do { save(try StoreRecoveryArchive.capture(storeURL: Self.storeURL), name: "Sonar-资料库恢复.json") }
        catch { errorMessage = error.localizedDescription }
    }

    private func save(_ data: Data, name: String, successMessage: String? = nil) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = name
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
                if let successMessage {
                    Task { @MainActor in self?.notice = successMessage }
                }
            } catch { Task { @MainActor in self?.errorMessage = "文件未能保存，请重试。" } }
        }
    }

    func showNotch() {
        notchEnabled = true
        start()
        notchController?.expand(keyboard: true)
    }

    func toggleNotch() {
        if !notchEnabled { showNotch() }
        else { notchController?.toggleExpanded() }
    }

    private func observePlayback() {
        withObservationTracking {
            _ = playback.queue.current?.musicID
            _ = playback.state
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.synchronizePlayback()
                self.observePlayback()
            }
        }
    }

    private func synchronizePlayback() {
        let track = playback.queue.current
        if track?.musicID != observedTrackID {
            observedTrackID = track?.musicID
            recordedTrackID = nil
            artwork = nil
            lyrics = nil
            playback.updateNowPlayingArtwork(nil)
            detailTask?.cancel()
            if let track {
                detailTask = Task { [weak self] in
                    guard let self else { return }
                    async let image = self.artworkService?.image(for: track)
                    async let info = self.runtime.lyric(track)
                    if let image = try? await image, !Task.isCancelled, self.observedTrackID == track.musicID {
                        self.artwork = image
                        self.playback.updateNowPlayingArtwork(image)
                    }
                    if let info = try? await info, !Task.isCancelled, self.observedTrackID == track.musicID {
                        self.lyrics = LRCParser.document(lyric: info.lyric, translated: info.tlyric)
                    }
                    if let library = self.library, !Task.isCancelled,
                       let outcome = try? await self.detailRefresh.refresh(track, store: library),
                       case let .refreshed(refreshed) = outcome,
                       !Task.isCancelled, self.playback.queue.current?.musicID == track.musicID {
                        self.playback.updateTrackMetadata(refreshed)
                        self.reloadLibrary()
                    }
                }
            }
        }
        if playback.state == .playing, let track, recordedTrackID != track.musicID, let library {
            do {
                try library.recordRecent(track)
                recordedTrackID = track.musicID
                reloadLibrary()
            } catch { errorMessage = "最近播放未能保存，播放仍可继续。" }
        }
    }
}
