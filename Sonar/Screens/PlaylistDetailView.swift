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
            toastCenter.show(
                result.inserted
                    ? "已收藏到 \(result.playlist.name)"
                    : "歌曲已在 \(result.playlist.name) 中"
            )
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
    private let showsBackButton: Bool
    private let onOpenSettings: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.m3Scheme) private var scheme
    @Environment(\.trackDetailRefreshCoordinator) private var trackDetailRefreshCoordinator
    @Environment(PlaybackService.self) private var playbackService
    @Environment(ToastCenter.self) private var toastCenter

    @State private var selectedEntry: Entry?
    @State private var errorMessage: String?
    @State private var isSelecting = false
    @State private var selectedIDs: Set<String> = []

    init(
        playlist: Playlist,
        onBack: (() -> Void)? = nil,
        showsBackButton: Bool = true,
        onOpenSettings: (() -> Void)? = nil
    ) {
        self.playlist = playlist
        fallbackTitle = PersonalPlaylistDefaults.name
        fallbackSubtitle = PersonalPlaylistDefaults.name
        fallbackDescription = ""
        fallbackTracks = []
        self.onBack = onBack
        self.showsBackButton = showsBackButton
        self.onOpenSettings = onOpenSettings
    }

    init(title: String, subtitle: String, description: String, tracks: [Track]) {
        playlist = nil
        fallbackTitle = title
        fallbackSubtitle = subtitle
        fallbackDescription = description
        fallbackTracks = tracks
        onBack = nil
        showsBackButton = true
        onOpenSettings = nil
    }

    private var title: String {
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
            if isSelecting {
                selectionBar
            }

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
                await refreshTrackDetails(limit: 50, force: true)
            }
        }
        .task {
            await refreshTrackDetails()
        }
        .background(scheme.appSurface.ignoresSafeArea())
        .bottomChromeInset()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .ncmEdgeSwipeBack()
        .songActionsSheet(
            track: Binding(
                get: { selectedEntry?.track },
                set: { if $0 == nil { selectedEntry = nil } }
            ),
            onCollect: { value in
                selectedEntry = nil
                PersonalPlaylistCollectionFeedback.collect(
                    value,
                    context: modelContext,
                    toastCenter: toastCenter,
                    playbackService: playbackService
                )
            }
        ) { value in
            var actions = SongActionBuilder.standard(
                track: value,
                playback: playbackService,
                toast: toastCenter
            ) {
                selectedEntry = nil
                PersonalPlaylistCollectionFeedback.collect(
                    value,
                    context: modelContext,
                    toastCenter: toastCenter,
                    playbackService: playbackService
                )
            }
            if let entry = selectedEntry, let playlist, !playlist.isSystem, entry.playlistIndex != nil {
                actions.append(SongAction(
                    title: "移出歌单",
                    systemImage: "text.badge.minus",
                    role: .destructive
                ) {
                    selectedEntry = nil
                    remove(entry, from: playlist)
                })
            }
            return actions
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
            if showsBackButton {
                Button(action: navigateBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(scheme.onSurface)
                        .frame(width: 44, height: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("返回")
                .accessibilityIdentifier("playlist-detail-back")
            } else if let onOpenSettings {
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(scheme.onSurface)
                        .frame(width: 44, height: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("设置")
                .accessibilityIdentifier("playlist-detail-settings")
            }

            Spacer()

            if !entries.isEmpty {
                Button(isSelecting ? "取消" : "选择") {
                    if isSelecting {
                        isSelecting = false
                        selectedIDs.removeAll()
                    } else {
                        isSelecting = true
                    }
                }
                .font(.system(size: 15))
                .foregroundStyle(scheme.onSurface)
                .frame(height: 44)
                .accessibilityIdentifier("playlist-detail-select")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    private var selectionBar: some View {
        HStack(spacing: 12) {
            Button(allSelected ? "取消全选" : "全选") {
                if allSelected {
                    selectedIDs.removeAll()
                } else {
                    selectedIDs = Set(entries.map(\.id))
                }
            }
            .font(.system(size: 14))
            .foregroundStyle(scheme.onSurface)

            Text("已选 \(selectedIDs.count)")
                .font(.system(size: 14))
                .foregroundStyle(scheme.onSurfaceVariant)

            Spacer(minLength: 0)

            Button("入队") { enqueueSelected() }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(scheme.onSurface)
                .disabled(selectedIDs.isEmpty)
                .accessibilityIdentifier("playlist-select-enqueue")

            if let playlist, !playlist.isSystem {
                Button("移出") { removeSelected() }
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(scheme.primary)
                    .disabled(selectedIDs.isEmpty)
                    .accessibilityIdentifier("playlist-select-remove")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(scheme.surfaceContainer)
    }

    private var allSelected: Bool {
        !entries.isEmpty && selectedIDs.count == entries.count
    }

    private var selectedEntries: [Entry] {
        entries.filter { selectedIDs.contains($0.id) }
    }

    private func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }

    private func collectSelected() {
        let values = selectedEntries.map(\.track)
        guard !values.isEmpty else { return }
        let store = LibraryStore(context: modelContext)
        var inserted = 0
        for track in values {
            if let result = try? store.collect(track), result.inserted { inserted += 1 }
        }
        toastCenter.show("已收藏 \(inserted) 首")
        isSelecting = false
        selectedIDs.removeAll()
    }

    private func enqueueSelected() {
        let values = selectedEntries.map(\.track)
        guard !values.isEmpty else { return }
        Task {
            var added = 0
            for track in values {
                if await playbackService.enqueue(track) { added += 1 }
            }
            toastCenter.show("已加入待播放 \(added) 首")
            isSelecting = false
            selectedIDs.removeAll()
        }
    }

    private func removeSelected() {
        guard let playlist, !playlist.isSystem else { return }
        let indices = selectedEntries.compactMap(\.playlistIndex).sorted(by: >)
        guard !indices.isEmpty else { return }
        let store = LibraryStore(context: modelContext)
        do {
            for index in indices {
                try store.removeItem(at: index, from: playlist)
            }
            toastCenter.show("已移出 \(indices.count) 首")
            isSelecting = false
            selectedIDs.removeAll()
        } catch {
            errorMessage = error.localizedDescription
        }
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
                        trailing: isSelecting ? .collectionStatus(selectedIDs.contains(entry.id)) : .more,
                        showAlbum: false,
                        showDivider: index < entries.count - 1,
                        isCurrent: playbackService.queue.current?.musicID == entry.track.musicID,
                        isPlaying: playbackService.state == .playing,
                        onPlay: {
                            if isSelecting {
                                toggleSelection(entry.id)
                            } else {
                                Task { await playbackService.replaceQueue(tracks, startingAt: index, activePlaylistID: playlist?.id) }
                            }
                        },
                        onAction: isSelecting ? { toggleSelection(entry.id) } : { selectedEntry = entry }
                    )
                    .contextMenu {
                        Button("立即播放", systemImage: "play.fill") {
                            Task { await playbackService.replaceQueue(tracks, startingAt: index, activePlaylistID: playlist?.id) }
                        }
                        .disabled(!entry.track.source.isEnabled)
                        Button("下一首播放", systemImage: "text.line.first.and.arrowtriangle.forward") {
                            Task {
                                await playbackService.playNext(entry.track)
                                toastCenter.show("已设为下一首播放")
                            }
                        }
                        .disabled(!entry.track.source.isEnabled)
                        Button("加入待播放", systemImage: "text.badge.plus") {
                            Task {
                                let added = await playbackService.enqueue(entry.track)
                                toastCenter.show(added ? "已加入待播放" : "歌曲已在待播放中")
                            }
                        }
                        .disabled(!entry.track.source.isEnabled)
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
        .disabled(!tracks.contains(where: { $0.source.isEnabled }))
        .opacity(tracks.contains(where: { $0.source.isEnabled }) ? 1 : 0.45)
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
        .disabled(!tracks.contains(where: { $0.source.isEnabled }))
        .opacity(tracks.contains(where: { $0.source.isEnabled }) ? 1 : 0.45)
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

    private func refreshTrackDetails(limit: Int = 20, force: Bool = false) async {
        guard let trackDetailRefreshCoordinator else { return }
        let candidates = tracks.filter { $0.source.isEnabled && (force || $0.highestKnownQuality == .standard) }
        guard !candidates.isEmpty else { return }
        let store = LibraryStore(context: modelContext)

        for track in candidates.prefix(limit) {
            if Task.isCancelled { break }
            do {
                let outcome = try await trackDetailRefreshCoordinator.refresh(track, store: store, force: force)
                if case let .refreshed(refreshed) = outcome {
                    try Task.checkCancellation()
                    playbackService.updateTrackMetadata(refreshed)
                }
            } catch is CancellationError {
                return
            } catch {
                // Existing metadata remains usable and the coordinator persists retry backoff.
            }
            do {
                try await Task.sleep(for: .milliseconds(80))
            } catch {
                return
            }
        }
    }
}
