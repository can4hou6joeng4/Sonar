import CryptoKit
import Foundation
import Observation
import SwiftUI

public struct LyricsCachePolicy: Sendable {
    public static let currentVersion = 1
    public static let production = LyricsCachePolicy()

    public let ttl: TimeInterval
    public let diskBytes: Int

    public init(
        ttl: TimeInterval = 30 * 24 * 60 * 60,
        diskBytes: Int = 32 * 1024 * 1024
    ) {
        self.ttl = max(0, ttl)
        self.diskBytes = max(0, diskBytes)
    }
}

private struct LyricsCacheEnvelope: Codable {
    let version: Int
    let musicID: String
    let fetchedAt: Date
    let info: LyricInfo
}

public actor LyricsService {
    private struct Pending {
        let id: UUID
        let task: Task<Void, Never>
        let stale: LyricInfo?
        var waiters: [UUID: CheckedContinuation<LyricInfo, Error>]
    }

    private let sourceRuntime: SourceRuntime
    private let cacheDirectory: URL?
    private let policy: LyricsCachePolicy
    private var pending: [String: Pending] = [:]

    public init(
        sourceRuntime: SourceRuntime,
        cacheDirectory: URL? = nil,
        policy: LyricsCachePolicy = .production
    ) {
        self.sourceRuntime = sourceRuntime
        self.policy = policy
        let resolvedDirectory: URL?
        if let cacheDirectory {
            resolvedDirectory = cacheDirectory
        } else {
            resolvedDirectory = try? FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("Lyrics", isDirectory: true)
        }
        if let resolvedDirectory {
            do {
                try FileManager.default.createDirectory(
                    at: resolvedDirectory,
                    withIntermediateDirectories: true
                )
                self.cacheDirectory = resolvedDirectory
                Self.trimDisk(directory: resolvedDirectory, limit: policy.diskBytes)
            } catch {
                self.cacheDirectory = nil
            }
        } else {
            self.cacheDirectory = nil
        }
    }

    public func lyrics(for track: Track, now: Date = Date()) async throws -> LyricInfo {
        try Task.checkCancellation()
        let key = track.musicID
        let cached = readEntry(for: key)
        if let cached, cached.fetchedAt.addingTimeInterval(policy.ttl) > now {
            touchEntry(for: key, at: now)
            return cached.info
        }

        let waiterID = UUID()
        let value: LyricInfo = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                if pending[key] != nil {
                    pending[key]?.waiters[waiterID] = continuation
                    return
                }
                let requestID = UUID()
                let runtime = sourceRuntime
                let task = Task {
                    do {
                        let info = try await runtime.lyric(track)
                        try Task.checkCancellation()
                        self.finish(
                            key: key,
                            requestID: requestID,
                            result: .success(info),
                            fetchedAt: now
                        )
                    } catch {
                        self.finish(
                            key: key,
                            requestID: requestID,
                            result: .failure(error),
                            fetchedAt: now
                        )
                    }
                }
                pending[key] = Pending(
                    id: requestID,
                    task: task,
                    stale: cached?.info,
                    waiters: [waiterID: continuation]
                )
            }
        } onCancel: {
            Task { await self.cancelWaiter(key: key, waiterID: waiterID) }
        }
        try Task.checkCancellation()
        return value
    }

    func cacheUsage() -> (diskBytes: Int, entries: Int, pendingConsumers: Int) {
        guard let cacheDirectory else {
            return (0, 0, pending.values.reduce(0) { $0 + $1.waiters.count })
        }
        let files = Self.cacheFiles(in: cacheDirectory)
        return (
            files.reduce(0) { $0 + $1.size },
            files.count,
            pending.values.reduce(0) { $0 + $1.waiters.count }
        )
    }

    private func cancelWaiter(key: String, waiterID: UUID) {
        guard let continuation = pending[key]?.waiters.removeValue(forKey: waiterID) else { return }
        continuation.resume(throwing: CancellationError())
        if pending[key]?.waiters.isEmpty == true {
            pending.removeValue(forKey: key)?.task.cancel()
        }
    }

    private func finish(
        key: String,
        requestID: UUID,
        result: Result<LyricInfo, Error>,
        fetchedAt: Date
    ) {
        guard let request = pending[key], request.id == requestID else { return }
        pending[key] = nil

        let delivered: Result<LyricInfo, Error>
        switch result {
        case let .success(info):
            write(info, for: key, fetchedAt: fetchedAt)
            delivered = .success(info)
        case let .failure(error):
            if Self.isCancellation(error) {
                delivered = .failure(CancellationError())
            } else if let stale = request.stale {
                delivered = .success(stale)
            } else {
                delivered = .failure(error)
            }
        }
        for waiter in request.waiters.values { waiter.resume(with: delivered) }
    }

    private func readEntry(for key: String) -> LyricsCacheEnvelope? {
        guard let url = cacheURL(for: key),
              let data = try? Data(contentsOf: url),
              let envelope = try? JSONDecoder().decode(LyricsCacheEnvelope.self, from: data),
              envelope.version == LyricsCachePolicy.currentVersion,
              envelope.musicID == key else {
            if let url = cacheURL(for: key) { try? FileManager.default.removeItem(at: url) }
            return nil
        }
        return envelope
    }

    private func write(_ info: LyricInfo, for key: String, fetchedAt: Date) {
        guard policy.diskBytes > 0,
              let cacheDirectory,
              let url = cacheURL(for: key),
              let data = try? JSONEncoder().encode(LyricsCacheEnvelope(
                version: LyricsCachePolicy.currentVersion,
                musicID: key,
                fetchedAt: fetchedAt,
                info: info
              )),
              data.count <= policy.diskBytes else { return }
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.modificationDate: fetchedAt], ofItemAtPath: url.path)
            Self.trimDisk(directory: cacheDirectory, limit: policy.diskBytes)
        } catch {
            // Fresh lyrics remain usable when the disposable disk cache is unavailable.
        }
    }

    private func touchEntry(for key: String, at date: Date) {
        guard let url = cacheURL(for: key) else { return }
        try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    private func cacheURL(for key: String) -> URL? {
        guard let cacheDirectory else { return nil }
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return cacheDirectory.appendingPathComponent("\(digest).lyrics")
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        return (error as? URLError)?.code == .cancelled
    }

    private static func cacheFiles(in directory: URL) -> [(url: URL, size: Int, modified: Date)] {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        return ((try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys)
        )) ?? []).compactMap { url in
            guard url.pathExtension == "lyrics",
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { return nil }
            return (url, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
    }

    private static func trimDisk(directory: URL, limit: Int) {
        var files = cacheFiles(in: directory)
        if limit == 0 {
            for file in files { try? FileManager.default.removeItem(at: file.url) }
            return
        }
        for file in files where file.size > limit {
            try? FileManager.default.removeItem(at: file.url)
        }
        files = cacheFiles(in: directory)
        var total = files.reduce(0) { $0 + $1.size }
        for file in files.sorted(by: {
            $0.modified == $1.modified ? $0.url.path < $1.url.path : $0.modified < $1.modified
        }) where total > limit {
            do {
                try FileManager.default.removeItem(at: file.url)
                total -= file.size
            } catch { continue }
        }
    }
}

@MainActor
@Observable
final class PlayerLyricsModel {
    private(set) var info: LyricInfo?
    private(set) var document = LyricsDocument(lines: [])
    private(set) var karaoke = KaraokeLyrics()
    private(set) var errorMessage: String?

    func load(track: Track?, service: LyricsService?) async {
        info = nil
        document = LyricsDocument(lines: [])
        karaoke = KaraokeLyrics()
        errorMessage = nil
        guard let track, let service else { return }
        do {
            let value = try await service.lyrics(for: track)
            guard !Task.isCancelled else { return }
            info = value
            document = LRCParser.document(lyric: value.lyric, translated: value.tlyric)
            karaoke = KaraokeLyrics(info: value)
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }
}

enum PlayerSurface: String, CaseIterable, Identifiable {
    case artwork
    case lyrics
    case queue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .artwork: "封面"
        case .lyrics: "歌词"
        case .queue: "待播放"
        }
    }

    var systemImage: String {
        switch self {
        case .artwork: "square.stack"
        case .lyrics: "quote.bubble"
        case .queue: "list.bullet"
        }
    }

    var order: Int {
        switch self {
        case .artwork: 0
        case .lyrics: 1
        case .queue: 2
        }
    }

    func direction(to destination: Self) -> PlayerSurfaceTransitionDirection {
        if destination.order > order { return .forward }
        if destination.order < order { return .backward }
        return .stationary
    }
}

enum PlayerSurfaceTransitionDirection: Int, Equatable {
    case backward = -1
    case stationary = 0
    case forward = 1
}

struct PlayerPage: View {
    private enum PresentedSheet: Identifiable {
        case cover(Track)
        case quality(Track)

        var id: String {
            switch self {
            case .cover: "cover"
            case .quality: "quality"
            }
        }
    }

    let pullController: PlayerPullController
    let viewportHeight: CGFloat
    @Binding var selectedSurface: PlayerSurface
    let onClose: () -> Void

    @Environment(PlaybackService.self) private var playbackService
    @Environment(ToastCenter.self) private var toastCenter
    @Environment(\.modelContext) private var modelContext
    @Environment(\.sonarReduceMotion) private var reduceMotion
    @Environment(\.lyricsService) private var lyricsService
    @State private var lyricsModel = PlayerLyricsModel()
    @State private var presentedSheet: PresentedSheet?

    var body: some View {
        ZStack {
            FlowingLightBackground(track: playbackService.queue.current)

            VStack(spacing: 0) {
                PlayerTopBar(
                    selectedSurface: selectedSurface,
                    onClose: closePlayer,
                    onMore: showMore
                )

                PlayerSurfaceContent(
                    selectedSurface: selectedSurface,
                    lyricsModel: lyricsModel,
                    pullController: pullController,
                    onShowLyrics: { selectedSurface = .lyrics },
                    onShowArtwork: { selectedSurface = .artwork }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                TransportBar(onOpenQueue: {
                    selectedSurface = (selectedSurface == .queue ? .artwork : .queue)
                })
                .padding(.bottom, 16)
            }
        }
        .foregroundStyle(NCMDesignTokens.Player.primaryInk)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .task(id: playbackService.queue.current?.musicID) {
            await lyricsModel.load(track: playbackService.queue.current, service: lyricsService)
        }
        .onChange(of: pullController.pull) { _, pull in
            if pull == 0 { selectedSurface = .artwork }
        }
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case let .cover(track):
                CoverActionsSheet(
                    track: track,
                    onAddToQueue: {
                        presentedSheet = nil
                        Task {
                            let added = await playbackService.enqueue(track)
                            toastCenter.show(added ? "已加入待播放" : "歌曲已在待播放中")
                        }
                    },
                    onCollect: {
                        presentedSheet = nil
                        PersonalPlaylistCollectionFeedback.collect(
                            track,
                            context: modelContext,
                            toastCenter: toastCenter,
                            playbackService: playbackService
                        )
                    },
                    onSelectQuality: { transitionSheet(to: .quality(track)) }
                )
                .presentationDetents([.fraction(0.62)])
                .presentationDragIndicator(.visible)
            case let .quality(track):
                QualitySheet(track: track)
                    .presentationDetents([.fraction(0.72)])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private func closePlayer() {
        selectedSurface = .artwork
        onClose()
    }

    private func showMore() {
        guard let track = playbackService.queue.current else { return }
        presentedSheet = .cover(track)
    }

    private func transitionSheet(to destination: PresentedSheet) {
        presentedSheet = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 180))
            guard !Task.isCancelled else { return }
            presentedSheet = destination
        }
    }
}

private struct PlayerSurfaceContent: View {
    let selectedSurface: PlayerSurface
    let lyricsModel: PlayerLyricsModel
    let pullController: PlayerPullController
    let onShowLyrics: () -> Void
    let onShowArtwork: () -> Void

    @Environment(\.sonarReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                VStack(spacing: 0) {
                    AlbumFace(
                        expansionProgress: pullController.pull,
                        onCoverAction: onShowLyrics
                    )
                    .playerDismissGesture(controller: pullController)
                    PlayerMetadata(compact: false)
                }
                .playerSurfaceState(
                    surface: .artwork,
                    selection: selectedSurface,
                    width: proxy.size.width,
                    reduceMotion: reduceMotion
                )
                .accessibilityIdentifier("player-artwork-surface")

                VStack(spacing: 0) {
                    PlayerMetadata(compact: true)
                    KaraokeLyricsView(
                        lyrics: lyricsModel.karaoke,
                        errorMessage: lyricsModel.errorMessage,
                        edgeFadeEnabled: true
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onShowArtwork()
                    }
                }
                .playerSurfaceState(
                    surface: .lyrics,
                    selection: selectedSurface,
                    width: proxy.size.width,
                    reduceMotion: reduceMotion
                )
                .accessibilityIdentifier("player-lyrics-surface")

                VStack(spacing: 0) {
                    QueueFace(presentation: .player)
                }
                .playerSurfaceState(
                    surface: .queue,
                    selection: selectedSurface,
                    width: proxy.size.width,
                    reduceMotion: reduceMotion
                )
                .accessibilityIdentifier("player-queue-surface")
            }
            .animation(
                reduceMotion ? .easeOut(duration: AppMotion.short) : AppMotion.emphasized(duration: AppMotion.medium, reduceMotion: false),
                value: selectedSurface
            )
        }
    }
}

private extension View {
    func playerSurfaceState(
        surface: PlayerSurface,
        selection: PlayerSurface,
        width: CGFloat,
        reduceMotion: Bool
    ) -> some View {
        let direction = selection.direction(to: surface)
        let travel = min(width * 0.12, 44)
        return opacity(surface == selection ? 1 : 0)
            .offset(x: reduceMotion ? 0 : CGFloat(direction.rawValue) * travel)
            .allowsHitTesting(surface == selection)
            .accessibilityHidden(surface != selection)
    }
}

private struct PlayerTopBar: View {
    let selectedSurface: PlayerSurface
    let onClose: () -> Void
    let onMore: () -> Void

    @Environment(PlaybackService.self) private var playbackService

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onClose) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.circleIcon(diameter: 38))
            .accessibilityLabel("收起播放页")
            .accessibilityHint("返回当前页面")

            VStack(spacing: 1) {
                Text("正在播放")
                    .font(.subheadline.weight(.semibold))
                Text(selectedSurface.title)
                    .font(.caption2)
                    .foregroundStyle(NCMDesignTokens.Player.secondaryInk)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)

            Button(action: onMore) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.circleIcon(diameter: 38))
            .disabled(playbackService.queue.current == nil)
            .accessibilityLabel("更多")
            .accessibilityIdentifier("player-cover-menu-button")
        }
        .padding(.horizontal, 8)
        .frame(height: 48)
    }
}

private struct PlayerMetadata: View {
    let compact: Bool

    @Environment(PlaybackService.self) private var playbackService

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if compact {
                PlayerArtwork(
                    track: playbackService.queue.current,
                    size: 48,
                    cornerRadius: 6
                )
                .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(playbackService.queue.current?.title ?? "暂无播放")
                    .font(compact ? .headline : .title3.weight(.semibold))
                    .lineLimit(compact ? 1 : 2)
                Text(playbackService.queue.current?.artist ?? "选择歌曲开始播放")
                    .font(.subheadline)
                    .foregroundStyle(NCMDesignTokens.Player.secondaryInk)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
        .padding(.vertical, 6)
        .frame(minHeight: compact ? 60 : 66)
    }
}
