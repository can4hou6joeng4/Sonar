import Observation
import SwiftUI

@MainActor
@Observable
final class PlayerLyricsModel {
    private(set) var info: LyricInfo?
    private(set) var document = LyricsDocument(lines: [])
    private(set) var karaoke = KaraokeLyrics()
    private(set) var errorMessage: String?

    func load(track: Track?, runtime: SourceRuntime) async {
        info = nil
        document = LyricsDocument(lines: [])
        karaoke = KaraokeLyrics()
        errorMessage = nil
        guard let track else { return }
        do {
            let value = try await runtime.lyric(track)
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

    let sourceRuntime: SourceRuntime
    let pullController: PlayerPullController
    let viewportHeight: CGFloat
    @Binding var selectedSurface: PlayerSurface
    let onClose: () -> Void

    @Environment(PlaybackService.self) private var playbackService
    @Environment(ToastCenter.self) private var toastCenter
    @Environment(\.modelContext) private var modelContext
    @Environment(\.sonarReduceMotion) private var reduceMotion
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
            await lyricsModel.load(track: playbackService.queue.current, runtime: sourceRuntime)
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

