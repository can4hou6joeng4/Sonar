import SwiftData
import SwiftUI

struct SongsView: View {
    private enum PlaylistSection: String, CaseIterable, Identifiable {
        case created = "创建"
        case favorite = "收藏"
        var id: String { rawValue }
    }

    let isActive: Bool

    @Environment(PlaybackService.self) private var playbackService
    @Environment(ToastCenter.self) private var toastCenter
    @Environment(\.modelContext) private var modelContext
    @Environment(\.m3Scheme) private var scheme
    @Environment(\.shellSafeAreaInsets) private var safeAreaInsets
    @Query(sort: \TrackRecord.title) private var allRecords: [TrackRecord]
    @Query(sort: \Playlist.sortIndex) private var allPlaylists: [Playlist]

    @State private var section: PlaylistSection = .created
    @State private var favoriteIDs = Set<UUID>()
    @State private var selectedPlaylistID: UUID?
    @State private var showingRecent = false
    @State private var showingLocal = false
    @State private var showingSettings = false
    @State private var showingCreate = false
    @State private var newPlaylistName = ""
    @State private var playlistToRename: Playlist?
    @State private var renameText = ""
    @State private var playlistToDelete: Playlist?
    @State private var errorMessage: String?

    private var userPlaylists: [Playlist] { allPlaylists.filter { !$0.isSystem } }
    private var createdPlaylists: [Playlist] { userPlaylists.filter { !favoriteIDs.contains($0.id) } }
    private var favoritePlaylists: [Playlist] { userPlaylists.filter { favoriteIDs.contains($0.id) } }
    private var visiblePlaylists: [Playlist] { section == .created ? createdPlaylists : favoritePlaylists }
    private var recentTracks: [Track] {
        allPlaylists.first { $0.id == LibraryStore.recentPlaylistID }?.items
            .sorted { $0.sortIndex < $1.sortIndex }
            .compactMap { $0.track.track } ?? []
    }
    private var selectedPlaylist: Playlist? {
        guard let selectedPlaylistID else { return nil }
        return userPlaylists.first { $0.id == selectedPlaylistID }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                hero
                shortcuts
                    .padding(.top, 12)
                sectionTabs
                    .padding(.top, 18)
                playlistRows
                Color.clear.frame(height: 24)
            }
        }
        .scrollIndicators(.hidden)
        .background(scheme.appSurface.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .ignoresSafeArea(edges: .top)
        .navigationDestination(isPresented: $showingRecent) {
            PlaylistDetailView(
                title: "最近播放",
                subtitle: "最近播放",
                description: "按最近成功播放的顺序排列。",
                tracks: recentTracks
            )
        }
        .navigationDestination(isPresented: $showingLocal) { LocalSongsView() }
        .navigationDestination(isPresented: $showingSettings) { SettingsView() }
        .navigationDestination(isPresented: selectedPlaylistBinding) {
            if let selectedPlaylist { PlaylistDetailView(playlist: selectedPlaylist) }
        }
        .onAppear(perform: refreshFavorites)
        .onChange(of: userPlaylists.map(\.id)) { _, _ in refreshFavorites() }
        .alert("新建歌单", isPresented: $showingCreate) {
            TextField("歌单名称", text: $newPlaylistName)
            Button("取消", role: .cancel) { newPlaylistName = "" }
            Button("创建", action: createPlaylist)
        }
        .alert("重命名歌单", isPresented: Binding(
            get: { playlistToRename != nil },
            set: { if !$0 { playlistToRename = nil } }
        )) {
            TextField("歌单名称", text: $renameText)
            Button("取消", role: .cancel) { playlistToRename = nil }
            Button("保存", action: renamePlaylist)
        }
        .confirmationDialog(
            "删除「\(playlistToDelete?.name ?? "")」？",
            isPresented: Binding(
                get: { playlistToDelete != nil },
                set: { if !$0 { playlistToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除歌单", role: .destructive, action: deletePlaylist)
            Button("取消", role: .cancel) { playlistToDelete = nil }
        } message: {
            Text("曲目仍会保留在本地曲库中。")
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

    private var hero: some View {
        GeometryReader { proxy in
            ZStack {
                PlayerArtwork(track: playbackService.queue.current, size: 560, cornerRadius: 0)
                    .blur(radius: 34)
                    .saturation(1.35)
                    .scaleEffect(1.25)
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.34), location: 0),
                        .init(color: .black.opacity(0.22), location: 0.84),
                        .init(color: scheme.appSurface, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("我的")
                        .font(.system(size: NCMDesignTokens.Typography.libraryTitle, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.45), radius: 6, y: 1)
                    Text("\(allRecords.count) 首歌曲 · \(createdPlaylists.count) 个歌单 · \(favoritePlaylists.count) 个收藏")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.80))
                        .shadow(color: .black.opacity(0.45), radius: 5, y: 1)
                }
                .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
                .padding(.bottom, 54)
            }
            .clipped()
        }
        .frame(height: safeAreaInsets.top + 156)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("library-hero")
    }

    private var shortcuts: some View {
        HStack(spacing: NCMDesignTokens.Layout.shortcutSpacing) {
            shortcut("最近", icon: "clock") { showingRecent = true }
            shortcut("本地", icon: "arrow.down.circle") { showingLocal = true }
            shortcut("喜欢", icon: "heart") { openLikedPlaylist() }
            shortcut("设置", icon: "gearshape") { showingSettings = true }
        }
        .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
    }

    private func shortcut(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 13, weight: .semibold))
                Text(title).font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(scheme.onSurface)
            .frame(maxWidth: .infinity)
            .frame(height: NCMDesignTokens.Layout.shortcutHeight)
            .background(scheme.surfaceContainer, in: RoundedRectangle(cornerRadius: NCMDesignTokens.Layout.shortcutCornerRadius))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library-shortcut-\(title)")
    }

    private var sectionTabs: some View {
        HStack(spacing: 26) {
            sectionTab(.created, count: createdPlaylists.count)
            sectionTab(.favorite, count: favoritePlaylists.count)
            Spacer(minLength: 0)
            Button("新建") {
                newPlaylistName = ""
                showingCreate = true
            }
            .font(.system(size: 13))
            .foregroundStyle(scheme.onSurfaceVariant)
            .frame(minHeight: 44)
            .buttonStyle(.plain)
            .accessibilityIdentifier("playlist-create-button")
        }
        .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
    }

    private func sectionTab(_ value: PlaylistSection, count: Int) -> some View {
        Button {
            section = value
        } label: {
            VStack(spacing: 5) {
                Text("\(value.rawValue) \(count)")
                    .font(.system(size: section == value ? 17 : 16, weight: section == value ? .bold : .regular))
                    .foregroundStyle(section == value ? scheme.onSurface : scheme.onSurfaceVariant)
                Capsule()
                    .fill(section == value ? scheme.primary : Color.clear)
                    .frame(width: 18, height: 3)
            }
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var playlistRows: some View {
        if visiblePlaylists.isEmpty {
            ContentUnavailableView(
                section == .created ? "还没有创建的歌单" : "还没有收藏的歌单",
                systemImage: section == .created ? "music.note.list" : "heart",
                description: Text(section == .created ? "点右上角的新建开始整理歌曲。" : "在在线歌单详情中可以收藏完整歌单。")
            )
            .frame(minHeight: 220)
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(visiblePlaylists.enumerated()), id: \.element.id) { index, playlist in
                    playlistRow(playlist, showDivider: index < visiblePlaylists.count - 1)
                }
            }
        }
    }

    private func playlistRow(_ playlist: Playlist, showDivider: Bool) -> some View {
        HStack(spacing: 12) {
            Button {
                selectedPlaylistID = playlist.id
            } label: {
                HStack(spacing: 12) {
                    PlayerArtwork(track: firstTrack(in: playlist), size: 50, cornerRadius: 8)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(playlist.name)
                            .font(.system(size: 16))
                            .foregroundStyle(scheme.onSurface)
                            .lineLimit(1)
                        Text("歌单 · \(playlist.items.count) 首")
                            .font(.system(size: 12))
                            .foregroundStyle(scheme.onSurfaceVariant)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Menu {
                Button("重命名", systemImage: "pencil") {
                    renameText = playlist.name
                    playlistToRename = playlist
                }
                Button("删除歌单", systemImage: "trash", role: .destructive) {
                    playlistToDelete = playlist
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(scheme.onSurfaceVariant)
                    .frame(width: 32, height: 44)
            }
            .accessibilityLabel("管理 \(playlist.name)")
        }
        .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
        .frame(height: NCMDesignTokens.Layout.playlistRowHeight)
        .overlay(alignment: .bottomTrailing) {
            if showDivider {
                Rectangle()
                    .fill(scheme.outlineVariant)
                    .frame(height: 0.5)
                    .padding(.leading, 78)
            }
        }
    }

    private var selectedPlaylistBinding: Binding<Bool> {
        Binding(
            get: { selectedPlaylistID != nil },
            set: { if !$0 { selectedPlaylistID = nil } }
        )
    }

    private func firstTrack(in playlist: Playlist) -> Track? {
        playlist.items.sorted { $0.sortIndex < $1.sortIndex }.first?.track.track
    }

    private func refreshFavorites() {
        favoriteIDs = FavoritePlaylistRegistry().prune(validPlaylistIDs: Set(userPlaylists.map(\.id)))
    }

    private func openLikedPlaylist() {
        do {
            let playlist: Playlist
            if let existing = userPlaylists.first(where: { $0.name == "我喜欢" }) {
                playlist = existing
            } else {
                playlist = try LibraryStore(context: modelContext).createPlaylist(named: "我喜欢")
            }
            selectedPlaylistID = playlist.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createPlaylist() {
        do {
            let playlist = try LibraryStore(context: modelContext).createPlaylist(named: newPlaylistName)
            newPlaylistName = ""
            section = .created
            selectedPlaylistID = playlist.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func renamePlaylist() {
        guard let playlistToRename else { return }
        do {
            try LibraryStore(context: modelContext).rename(playlistToRename, to: renameText)
            self.playlistToRename = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deletePlaylist() {
        guard let playlistToDelete else { return }
        do {
            try LibraryStore(context: modelContext).delete(playlistToDelete)
            FavoritePlaylistRegistry().unregister(playlistID: playlistToDelete.id)
            self.playlistToDelete = nil
            refreshFavorites()
            toastCenter.show("已删除歌单")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct LocalSongsView: View {
    private enum PresentedSheet: Identifiable {
        case actions(Track)
        case addToPlaylist(Track)

        var id: String {
            switch self {
            case let .actions(track): "actions-\(track.musicID)"
            case let .addToPlaylist(track): "add-\(track.musicID)"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(PlaybackService.self) private var playbackService
    @Environment(ToastCenter.self) private var toastCenter
    @Environment(\.m3Scheme) private var scheme
    @Query(sort: \TrackRecord.title) private var records: [TrackRecord]

    @State private var query = ""
    @State private var presentedSheet: PresentedSheet?

    private var tracks: [Track] {
        let values = records.compactMap(\.track)
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return values }
        return values.filter {
            [$0.title, $0.artist, $0.album].contains { $0.localizedCaseInsensitiveContains(keyword) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                TextField("搜索歌曲、歌手或专辑", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清空")
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(scheme.onSurfaceVariant)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(scheme.appInputFill, in: Capsule())
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            if tracks.isEmpty {
                ContentUnavailableView(
                    query.isEmpty ? "本地还没有歌曲" : "没有匹配的歌曲",
                    systemImage: "music.note.list"
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(tracks.enumerated()), id: \.element.musicID) { index, track in
                            SongRow(
                                track: track,
                                trailing: .more,
                                showDivider: index < tracks.count - 1,
                                isCurrent: playbackService.queue.current?.musicID == track.musicID,
                                isPlaying: playbackService.state == .playing,
                                onPlay: { Task { await playbackService.replaceQueue(tracks, startingAt: index) } },
                                onAction: { presentedSheet = .actions(track) }
                            )
                        }
                    }
                }
            }
        }
        .background(scheme.appSurface.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .ncmEdgeSwipeBack()
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case let .actions(track):
                LocalSongActionsSheet(
                    track: track,
                    onAddToPlaylist: { transitionToAddSheet(for: track) },
                    onDelete: { deleteTrack(track) }
                )
                .presentationDetents([.height(210)])
                .presentationDragIndicator(.visible)
            case let .addToPlaylist(track):
                AddToPlaylistSheet(track: track)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回")
            Text("本地歌曲")
                .font(.system(size: 22, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(records.count)")
                .font(.system(size: 13))
                .foregroundStyle(scheme.onSurfaceVariant)
                .frame(width: 44, height: 44)
        }
        .foregroundStyle(scheme.onSurface)
        .padding(.horizontal, 4)
        .padding(.top, 6)
    }

    private func transitionToAddSheet(for track: Track) {
        presentedSheet = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            presentedSheet = .addToPlaylist(track)
        }
    }

    private func deleteTrack(_ track: Track) {
        do {
            try LibraryStore(context: modelContext).deleteTrack(track)
            presentedSheet = nil
            toastCenter.show("已从曲库删除")
        } catch {
            toastCenter.show("删除失败：\(error.localizedDescription)")
        }
    }
}

private struct LocalSongActionsSheet: View {
    let track: Track
    let onAddToPlaylist: () -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.m3Scheme) private var scheme
    @State private var confirmingDelete = false

    var body: some View {
        VStack(spacing: 0) {
            Text(track.title)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
                .frame(height: 50)

            actionButton("加入歌单", systemImage: "text.badge.plus") {
                dismiss()
                onAddToPlaylist()
            }
            actionButton("从曲库删除", systemImage: "trash", role: .destructive) {
                confirmingDelete = true
            }
        }
        .foregroundStyle(scheme.onSurface)
        .background(scheme.appSurface.ignoresSafeArea())
        .confirmationDialog(
            "确定从曲库删除《\(track.title)》？",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) { onDelete() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这首歌会同时从最近播放和所有歌单中移除。")
        }
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(role: role, action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 15))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
                .frame(height: 54)
        }
        .buttonStyle(.plain)
    }
}

struct PlaylistsView: View {
    let playlists: [Playlist]

    var body: some View {
        SongsView(isActive: true)
    }
}
