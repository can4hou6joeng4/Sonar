import Observation
import SwiftData
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
    private enum Face: Int, Hashable {
        case vinyl
        case lyrics
        case queue
    }

    private enum PresentedSheet: Identifiable {
        case cover(Track)
        case addToPlaylist(Track)
        case quality(Track)

        var id: String {
            switch self {
            case .cover: "cover"
            case .addToPlaylist: "add-to-playlist"
            case .quality: "quality"
            }
        }
    }

    let sourceRuntime: SourceRuntime
    let pullController: PlayerPullController
    let viewportHeight: CGFloat
    let onClose: () -> Void

    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.sonarReduceMotion) private var reduceMotion
    @State private var selectedFace: Face = .vinyl
    @State private var lyricsModel = PlayerLyricsModel()
    @State private var presentedSheet: PresentedSheet?
    @State private var pageSwipeActive = false

    var body: some View {
        ZStack {
            FlowingLightBackground(track: playbackService.queue.current)

            VStack(spacing: 0) {
                PlayerTopBar(
                    onClose: closePlayer,
                    onMore: showMore
                )

                TabView(selection: $selectedFace) {
                    AlbumFace(lyrics: lyricsModel.document) {
                        selectedFace = .lyrics
                    }
                    .tag(Face.vinyl)
                    .playerDismissGesture(controller: pullController)
                    .accessibilityAction(named: Text("显示歌词")) {
                        selectedFace = .lyrics
                    }

                    KaraokeLyricsView(
                        lyrics: lyricsModel.karaoke,
                        errorMessage: lyricsModel.errorMessage,
                        edgeFadeEnabled: !pageSwipeActive
                    )
                    .tag(Face.lyrics)
                    .accessibilityAction(named: Text("显示封面")) {
                        selectedFace = .vinyl
                    }

                    QueueFace()
                        .tag(Face.queue)
                        .accessibilityAction(named: Text("显示封面")) {
                            selectedFace = .vinyl
                        }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(
                    AppMotion.emphasized(duration: AppMotion.long, reduceMotion: reduceMotion),
                    value: selectedFace
                )
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            pageSwipeActive = true
                        }
                        .onEnded { _ in pageSwipeActive = false }
                )
                .onChange(of: selectedFace) { _, _ in pageSwipeActive = false }

                PlayerMetadata()
                TransportBar {
                    selectedFace = selectedFace == .queue ? .vinyl : .queue
                }
                PlayerFooter(
                    isShowingLyrics: selectedFace == .lyrics,
                    onQuality: showQuality,
                    onLyrics: {
                        selectedFace = selectedFace == .lyrics ? .vinyl : .lyrics
                    },
                    onAddToPlaylist: showAddToPlaylist,
                    onMore: showMore
                )
                .padding(.bottom, 4)
            }
        }
        .foregroundStyle(NCMDesignTokens.Player.primaryInk)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .task(id: playbackService.queue.current?.musicID) {
            await lyricsModel.load(track: playbackService.queue.current, runtime: sourceRuntime)
        }
        .onChange(of: pullController.pull) { _, pull in
            if pull == 0 { selectedFace = .vinyl }
        }
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case let .cover(track):
                CoverActionsSheet(
                    track: track,
                    onAddToPlaylist: { transitionSheet(to: .addToPlaylist(track)) },
                    onSelectQuality: { transitionSheet(to: .quality(track)) }
                )
                .presentationDetents([.fraction(0.62)])
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

    private func closePlayer() {
        selectedFace = .vinyl
        onClose()
    }

    private func showMore() {
        guard let track = playbackService.queue.current else { return }
        presentedSheet = .cover(track)
    }

    private func showQuality() {
        guard let track = playbackService.queue.current else { return }
        presentedSheet = .quality(track)
    }

    private func showAddToPlaylist() {
        guard let track = playbackService.queue.current else { return }
        presentedSheet = .addToPlaylist(track)
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
    let onClose: () -> Void
    let onMore: () -> Void

    @Environment(PlaybackService.self) private var playbackService

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onClose) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 24, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("收起播放页")

            Text("正在播放")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(NCMDesignTokens.Player.secondaryInk)
                .frame(maxWidth: .infinity)

            Button(action: onMore) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(playbackService.queue.current == nil)
            .accessibilityLabel("更多")
            .accessibilityIdentifier("player-cover-menu-button")
        }
        .padding(.horizontal, 6)
        .frame(height: 46)
    }
}

private struct PlayerMetadata: View {
    @Environment(PlaybackService.self) private var playbackService

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(playbackService.queue.current?.title ?? "暂无播放")
                    .font(.system(size: NCMDesignTokens.Typography.playerTitle, weight: .semibold))
                    .lineLimit(1)
                Text(playbackService.queue.current?.artist ?? "选择歌曲开始播放")
                    .font(.system(size: NCMDesignTokens.Typography.playerArtist))
                    .foregroundStyle(NCMDesignTokens.Player.secondaryInk)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let track = playbackService.queue.current {
                PlayerFavoriteButton(track: track)
            }
        }
        .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
        .padding(.top, 6)
    }
}

private struct PlayerFavoriteButton: View {
    let track: Track

    @Environment(\.modelContext) private var modelContext
    @Environment(ToastCenter.self) private var toastCenter
    @Query(sort: \Playlist.sortIndex) private var playlists: [Playlist]

    private var likedPlaylist: Playlist? {
        playlists.first { !$0.isSystem && $0.name == "我喜欢" }
    }

    private var likedIndex: Int? {
        likedPlaylist?.items
            .sorted { $0.sortIndex < $1.sortIndex }
            .firstIndex { $0.track.musicId == track.musicID }
    }

    var body: some View {
        Button(action: toggleFavorite) {
            Image(systemName: likedIndex == nil ? "heart" : "heart.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(likedIndex == nil ? NCMDesignTokens.Player.secondaryInk : Color(hex: "#FF3738") ?? .red)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(likedIndex == nil ? "收藏" : "取消收藏")
        .accessibilityIdentifier("player-favorite-button")
    }

    private func toggleFavorite() {
        let store = LibraryStore(context: modelContext)
        do {
            if let likedPlaylist, let likedIndex {
                try store.removeItem(at: likedIndex, from: likedPlaylist)
                toastCenter.show("已取消喜欢")
            } else {
                let playlist = try likedPlaylist ?? store.createPlaylist(named: "我喜欢")
                _ = try store.add(track, to: playlist)
                toastCenter.show("已添加到我喜欢")
            }
        } catch {
            toastCenter.show("操作失败：\(error.localizedDescription)")
        }
    }
}

private struct PlayerFooter: View {
    let isShowingLyrics: Bool
    let onQuality: () -> Void
    let onLyrics: () -> Void
    let onAddToPlaylist: () -> Void
    let onMore: () -> Void

    @Environment(PlaybackService.self) private var playbackService

    var body: some View {
        HStack(spacing: 0) {
            footerButton(label: "音质", action: onQuality) {
                Text(playbackService.preferredQuality.badgeTitle.uppercased())
                    .font(.system(size: 9.5, weight: .bold))
            }
            footerButton(label: "歌词", action: onLyrics) {
                Image(systemName: "quote.bubble")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(isShowingLyrics ? NCMDesignTokens.Player.primaryInk : NCMDesignTokens.Player.tertiaryInk)
            }
            footerButton(label: "加入歌单", action: onAddToPlaylist) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 19, weight: .medium))
            }
            footerButton(label: "更多", action: onMore) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .medium))
            }
        }
        .padding(.horizontal, 26)
        .foregroundStyle(NCMDesignTokens.Player.tertiaryInk)
    }

    private func footerButton<Content: View>(
        label: String,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        Button(action: action) {
            content()
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(playbackService.queue.current == nil)
        .accessibilityLabel(label)
    }
}
