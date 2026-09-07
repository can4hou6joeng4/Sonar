import SwiftData
import SwiftUI
import UIKit

@MainActor
enum PersonalPlaylistCollectionFeedback {
    static func collect(
        _ track: Track,
        context: ModelContext,
        toastCenter: ToastCenter,
        playbackService: PlaybackService? = nil
    ) {
        do {
            let result = try LibraryStore(context: context).collect(track)
            if result.inserted {
                playbackService?.onTrackAddedToPlaylist(track, playlistID: result.playlist.id)
            }
            toastCenter.show(result.inserted ? "已收藏到歌单" : "歌曲已在歌单中")
        } catch {
            toastCenter.show("收藏失败：\(error.localizedDescription)")
        }
    }
}

struct PlaylistDetailView: View {
    private struct Entry: Identifiable {
        let id: String
        let track: Track
        let playlistIndex: Int?
    }

    private let playlist: Playlist?
    private let fallbackTitle: String
    private let fallbackSubtitle: String
    private let fallbackDescription: String
    private let fallbackTracks: [Track]
    private let onBack: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.m3Scheme) private var scheme
    @Environment(\.sourceRuntime) private var sourceRuntime
    @Environment(PlaybackService.self) private var playbackService
    @Environment(ToastCenter.self) private var toastCenter

    @State private var selectedEntry: Entry?
    @State private var errorMessage: String?

    init(playlist: Playlist, onBack: (() -> Void)? = nil) {
        self.playlist = playlist
        fallbackTitle = "我喜欢的音乐"
        fallbackSubtitle = "我喜欢的音乐"
        fallbackDescription = ""
        fallbackTracks = []
        self.onBack = onBack
    }

    init(title: String, subtitle: String, description: String, tracks: [Track]) {
        playlist = nil
        fallbackTitle = title
        fallbackSubtitle = subtitle
        fallbackDescription = description
        fallbackTracks = tracks
        onBack = nil
    }

    private var title: String {
        if isPersonalPlaylist { return "我喜欢的音乐" }
        return playlist?.name ?? fallbackTitle
    }
    private var isPersonalPlaylist: Bool { playlist == nil || playlist?.isPrimaryPersonal == true }
    private var tracks: [Track] { entries.map(\.track) }
    private var entries: [Entry] {
        if let playlist {
            return playlist.orderedItems.enumerated().compactMap { index, item in
                guard let track = item.track.track else { return nil }
                return Entry(id: track.musicID, track: track, playlistIndex: index)
            }
        }
        return fallbackTracks.enumerated().map { Entry(id: $0.element.musicID, track: $0.element, playlistIndex: nil) }
    }
    var body: some View {
        VStack(spacing: 0) {
            navigationBar

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerSection
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                        .padding(.bottom, 16)

                    playlistActions
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                    trackList
                }
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await refreshStandardQualityTracks(limit: 50)
            }
        }
        .task {
            await refreshStandardQualityTracks()
        }
        .background(scheme.appSurface.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .ncmEdgeSwipeBack()
        .confirmationDialog(
            selectedEntry.map { $0.track.title } ?? "歌曲操作",
            isPresented: Binding(
            get: { selectedEntry != nil },
            set: { if !$0 { selectedEntry = nil } }
        ), titleVisibility: .visible) {
            Button("立即播放", systemImage: "play.fill") {
                guard let selected = selectedEntry else { return }
                selectedEntry = nil
                let startIndex = selected.playlistIndex ?? tracks.firstIndex(where: { $0.musicID == selected.track.musicID }) ?? 0
                Task { await playbackService.replaceQueue(tracks, startingAt: startIndex, activePlaylistID: playlist?.id) }
            }
            Button("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward") {
                guard let track = selectedEntry?.track else { return }
                selectedEntry = nil
                Task {
                    await playbackService.playNext(track)
                    toastCenter.show("已设为下一首播放")
                }
            }
            Button("加入待播放", systemImage: "text.badge.plus") {
                guard let track = selectedEntry?.track else { return }
                selectedEntry = nil
                Task {
                    let added = await playbackService.enqueue(track)
                    toastCenter.show(added ? "已加入待播放" : "歌曲已在待播放中")
                }
            }
            Button("收藏到歌单", systemImage: "music.note.list") {
                guard let track = selectedEntry?.track else { return }
                selectedEntry = nil
                PersonalPlaylistCollectionFeedback.collect(
                    track,
                    context: modelContext,
                    toastCenter: toastCenter,
                    playbackService: playbackService
                )
            }
            if let entry = selectedEntry, let playlist, !playlist.isSystem, entry.playlistIndex != nil {
                Button("移出歌单", systemImage: "text.badge.minus", role: .destructive) {
                    remove(entry, from: playlist)
                }
            }
            Button("取消", role: .cancel) { selectedEntry = nil }
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private var navigationBar: some View {
        HStack(spacing: 0) {
            Button(action: navigateBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(scheme.onSurface)
                    .frame(width: 44, height: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回")
            .accessibilityIdentifier("playlist-detail-back")

            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(scheme.onSurface)
                .lineLimit(2)
                .accessibilityIdentifier(
                    isPersonalPlaylist
                        ? "personal-playlist-destination"
                        : "playlist-detail-title"
                )

            HStack(spacing: 6) {
                Text(heroMetadata)
                if let duration = totalDurationText {
                    Text("·")
                    Text(duration)
                }
            }
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(scheme.onSurfaceVariant)
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var trackList: some View {
        LazyVStack(spacing: 0) {
            playlistSongsHeader

            if entries.isEmpty {
                ContentUnavailableView {
                    Label("这个歌单还没有歌曲", systemImage: "music.note.list")
                } description: {
                    Text("在搜索结果或歌手页面选择“收藏到歌单”，歌曲会保存在这里。")
                }
                .frame(minHeight: 260)
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    SongRow(
                        track: entry.track,
                        leading: .index(index + 1),
                        trailing: .more,
                        showAlbum: false,
                        showDivider: index < entries.count - 1,
                        isCurrent: playbackService.queue.current?.musicID == entry.track.musicID,
                        isPlaying: playbackService.state == .playing,
                        onPlay: { Task { await playbackService.replaceQueue(tracks, startingAt: index, activePlaylistID: playlist?.id) } },
                        onAction: { selectedEntry = entry }
                    )
                    .contextMenu {
                        Button("立即播放", systemImage: "play.fill") {
                            Task { await playbackService.replaceQueue(tracks, startingAt: index, activePlaylistID: playlist?.id) }
                        }
                        Button("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward") {
                            Task {
                                await playbackService.playNext(entry.track)
                                toastCenter.show("已设为下一首播放")
                            }
                        }
                        Button("加入待播放", systemImage: "text.badge.plus") {
                            Task {
                                let added = await playbackService.enqueue(entry.track)
                                toastCenter.show(added ? "已加入待播放" : "歌曲已在待播放中")
                            }
                        }
                        Button("收藏到歌单", systemImage: "music.note.list") {
                            PersonalPlaylistCollectionFeedback.collect(
                                entry.track,
                                context: modelContext,
                                toastCenter: toastCenter,
                                playbackService: playbackService
                            )
                        }
                        if let playlist, !playlist.isSystem, entry.playlistIndex != nil {
                            Divider()
                            Button("移出歌单", systemImage: "trash", role: .destructive) {
                                remove(entry, from: playlist)
                            }
                        }
                    }
                }
            }
            Color.clear.frame(height: 146)
        }
        .background(scheme.appSurface)
    }

    private var playlistActions: some View {
        HStack(spacing: 12) {
            playAllButton
            shuffleButton
        }
        .accessibilityIdentifier(isPersonalPlaylist ? "personal-playlist-actions" : "playlist-actions")
    }

    private var playAllButton: some View {
        Button(action: playAllPlaylist) {
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                    .font(.system(size: 13, weight: .bold))
                HStack(spacing: 4) {
                    Text("播放全部")
                        .font(.system(size: 14, weight: .bold))
                    if !tracks.isEmpty {
                        Text("(\(tracks.count))")
                            .font(.system(size: 12, weight: .semibold))
                            .opacity(0.85)
                    }
                }
            }
            .foregroundStyle(scheme.onPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                LinearGradient(
                    colors: [scheme.primary, scheme.primary.opacity(0.88)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.bounce)
        .disabled(tracks.isEmpty)
        .opacity(tracks.isEmpty ? 0.45 : 1)
        .accessibilityLabel("播放全部")
        .accessibilityHint(tracks.isEmpty ? "歌单中还没有歌曲" : "按添加顺序播放歌单中的全部歌曲")
        .accessibilityIdentifier(isPersonalPlaylist ? "personal-playlist-play-all-button" : "playlist-play-all-button")
    }

    private var shuffleButton: some View {
        Button(action: shufflePlaylist) {
            HStack(spacing: 6) {
                Image(systemName: "shuffle")
                    .font(.system(size: 13, weight: .bold))
                Text("随机播放")
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(scheme.onSurface)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(scheme.surfaceContainerHigh)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.bounce)
        .disabled(tracks.isEmpty)
        .opacity(tracks.isEmpty ? 0.45 : 1)
        .accessibilityLabel("随机播放")
        .accessibilityHint(tracks.isEmpty ? "歌单中还没有歌曲" : "随机排列歌单并开始播放")
        .accessibilityIdentifier(isPersonalPlaylist ? "personal-playlist-shuffle-button" : "playlist-shuffle-button")
    }

    private var playlistSongsHeader: some View {
        Color.clear
            .frame(height: 2)
            .accessibilityIdentifier(isPersonalPlaylist ? "personal-playlist-songs-header" : "playlist-songs-header")
    }

    private func remove(_ entry: Entry, from playlist: Playlist) {
        guard let index = entry.playlistIndex else { return }
        do {
            try LibraryStore(context: modelContext).removeItem(at: index, from: playlist)
            playbackService.onTrackRemovedFromPlaylist(entry.track, playlistID: playlist.id)
            selectedEntry = nil
            toastCenter.show("已移出歌单")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func shufflePlaylist() {
        Task {
            let started = await playbackService.shuffleAndPlay(tracks, activePlaylistID: playlist?.id)
            guard started else {
                toastCenter.show("歌单中还没有歌曲")
                return
            }
            if tracks.count == 1 {
                toastCenter.show("已开始播放")
            } else {
                toastCenter.show("已随机播放 \(tracks.count) 首歌曲")
            }
        }
    }

    private func playAllPlaylist() {
        guard !tracks.isEmpty else {
            toastCenter.show("歌单中还没有歌曲")
            return
        }
        Task {
            // “播放全部” always means the persisted playlist order, even if
            // the player was previously left in shuffle mode.
            playbackService.setPlaybackMode(.sequence)
            await playbackService.replaceQueue(tracks, activePlaylistID: playlist?.id)
            toastCenter.show("已开始播放 \(tracks.count) 首歌曲")
        }
    }

    private var heroMetadata: String {
        if isPersonalPlaylist {
            return "\(tracks.count) 首歌曲"
        }
        if playlist != nil {
            return "\(playlist?.kind.title ?? "歌单") · \(tracks.count) 首歌曲"
        }
        return fallbackSubtitle
    }

    private var totalDurationText: String? {
        let seconds = tracks.compactMap(\.durationSeconds).reduce(0, +)
        guard seconds > 0 else { return nil }
        let totalSeconds = Int(seconds.rounded())
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        if hours > 0 {
            return "总时长 \(hours) 小时 \(minutes) 分钟"
        }
        return "总时长 \(minutes) 分钟"
    }

    private func navigateBack() {
        if let onBack {
            onBack()
        } else {
            dismiss()
        }
    }

    private func refreshStandardQualityTracks(limit: Int = 20) async {
        guard let sourceRuntime else { return }
        let candidates = tracks.filter { $0.highestKnownQuality == .standard }
        guard !candidates.isEmpty else { return }

        for track in candidates.prefix(limit) {
            if Task.isCancelled { break }
            do {
                let refreshed = try await sourceRuntime.trackDetail(track)
                if refreshed.highestKnownQuality != .standard || TrackQualityOption.available(for: refreshed).count > 1 {
                    await MainActor.run {
                        _ = try? LibraryStore(context: modelContext).updateTrack(refreshed)
                        playbackService.updateTrackMetadata(refreshed)
                    }
                }
            } catch {
                // Ignore failure gracefully for tracks that genuinely only have 128k or network glitch
            }
            try? await Task.sleep(for: .milliseconds(80))
        }
    }
}
