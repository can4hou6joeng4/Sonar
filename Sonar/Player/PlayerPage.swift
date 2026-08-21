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

struct PlayerPage: View {
    private enum PresentedSheet: Identifiable {
        case queue
        case cover(Track)
        case addToPlaylist(Track)
        case quality(Track)

        var id: String {
            switch self {
            case .queue: "queue"
            case .cover: "cover"
            case .addToPlaylist: "add-to-playlist"
            case .quality: "quality"
            }
        }
    }

    let sourceRuntime: SourceRuntime
    let pullController: PlayerPullController
    let viewportHeight: CGFloat

    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.playerPalette) private var palette
    @Environment(\.sonarReduceMotion) private var reduceMotion
    @State private var selectedPage = 0
    @State private var lyricsModel = PlayerLyricsModel()
    @State private var presentedSheet: PresentedSheet?
    @State private var pageSwipeActive = false

    var body: some View {
        ZStack {
            palette.surface
                .ignoresSafeArea()
            FlowingLightBackground(track: playbackService.queue.current)

            VStack(spacing: 0) {
                PlayerTopBar {
                    guard let track = playbackService.queue.current else { return }
                    presentedSheet = .cover(track)
                }
                    .playerPullHandle(controller: pullController, viewportHeight: viewportHeight)

                VStack(spacing: 0) {
                    TabView(selection: $selectedPage) {
                        AlbumFace(lyrics: lyricsModel.document) {
                            guard let track = playbackService.queue.current else { return }
                            presentedSheet = .cover(track)
                        }
                            .tag(0)
                            .playerPullHandle(controller: pullController, viewportHeight: viewportHeight)
                            .accessibilityAction(named: Text("显示歌词")) {
                                selectedPage = 1
                            }

                        KaraokeLyricsView(
                            lyrics: lyricsModel.karaoke,
                            errorMessage: lyricsModel.errorMessage,
                            edgeFadeEnabled: !pageSwipeActive
                        )
                        .tag(1)
                        .accessibilityAction(named: Text("显示封面")) {
                            selectedPage = 0
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(
                        AppMotion.emphasized(duration: AppMotion.long, reduceMotion: reduceMotion),
                        value: selectedPage
                    )
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 8)
                            .onChanged { value in
                                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                                pageSwipeActive = true
                            }
                            .onEnded { _ in pageSwipeActive = false }
                    )
                    .onChange(of: selectedPage) { _, _ in pageSwipeActive = false }

                    TransportBar {
                        presentedSheet = .queue
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 4)
                .padding(.bottom, 14)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .task(id: playbackService.queue.current?.musicID) {
            await lyricsModel.load(track: playbackService.queue.current, runtime: sourceRuntime)
        }
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .queue:
                QueueSheet()
                    .presentationDetents([.fraction(0.72)])
                    .presentationDragIndicator(.hidden)
                    .presentationBackground(palette.queueBackground)
            case let .cover(track):
                CoverActionsSheet(
                    track: track,
                    onAddToPlaylist: { transitionSheet(to: .addToPlaylist(track)) },
                    onSelectQuality: { transitionSheet(to: .quality(track)) }
                )
                .presentationDetents([.fraction(0.78)])
                .presentationDragIndicator(.visible)
            case let .addToPlaylist(track):
                AddToPlaylistSheet(track: track)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            case let .quality(track):
                QualitySheet(track: track)
                    .presentationDetents([.fraction(0.72)])
                    .presentationDragIndicator(.visible)
            }
        }
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

private struct PlayerTopBar: View {
    let onMore: () -> Void

    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.playerPalette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(playbackService.queue.current?.title ?? "暂无播放")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                Text(playbackService.queue.current?.artist ?? "选择一首歌曲开始播放")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(palette.muted.opacity(0.78))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onMore) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(palette.ink)
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.28), in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(playbackService.queue.current == nil)
            .accessibilityLabel("更多")
            .accessibilityIdentifier("player-cover-menu-button")
        }
        .padding(.leading, 28)
        .padding(.trailing, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}
