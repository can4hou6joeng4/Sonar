import SwiftData
import SwiftUI

struct SongsView: View {
    private struct Entry: Identifiable {
        let record: TrackRecord
        let playlistIndex: Int?
        var id: PersistentIdentifier { record.persistentModelID }
    }

    private enum PresentedSheet: Identifiable {
        case libraryView
        case addToPlaylist(Track)

        var id: String {
            switch self {
            case .libraryView: "library-view"
            case .addToPlaylist: "add-to-playlist"
            }
        }
    }

    let isActive: Bool

    @Environment(PlaybackService.self) private var playbackService
    @Environment(ToastCenter.self) private var toastCenter
    @Environment(\.modelContext) private var modelContext
    @Environment(\.m3Scheme) private var scheme
    @Environment(\.capsuleScrollReporter) private var capsuleScrollReporter
    @Query(sort: \TrackRecord.title) private var allRecords: [TrackRecord]
    @Query(filter: #Predicate<Playlist> { !$0.isSystem }, sort: \Playlist.sortIndex)
    private var playlists: [Playlist]

    @State private var selectedPlaylistID: UUID?
    @State private var presentedSheet: PresentedSheet?
    @State private var showingPlaylists = false
    @State private var isSearching = false
    @State private var searchQuery = ""
    @State private var lastScrollMarkerY: CGFloat?
    @State private var scrollSettleTask: Task<Void, Never>?
    @State private var errorMessage: String?

    private var selectedPlaylist: Playlist? {
        guard let selectedPlaylistID else { return nil }
        return playlists.first { $0.id == selectedPlaylistID }
    }

    private var title: String { selectedPlaylist?.name ?? "全部歌曲" }

    private var unfilteredEntries: [Entry] {
        guard let selectedPlaylist else {
            return allRecords.map { Entry(record: $0, playlistIndex: nil) }
        }
        return selectedPlaylist.items.sorted { $0.sortIndex < $1.sortIndex }.enumerated().map {
            Entry(record: $0.element.track, playlistIndex: $0.offset)
        }
    }

    private var entries: [Entry] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return unfilteredEntries }
        return unfilteredEntries.filter { entry in
            [entry.record.title, entry.record.artist, entry.record.album]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    private var tracks: [Track] { entries.compactMap(\.record.track) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if isSearching { searchField }
            countRow
            if entries.isEmpty {
                ContentUnavailableView(
                    "这个歌单还没有曲目",
                    systemImage: "music.note.list",
                    description: Text("搜索并播放歌曲后，它们会出现在曲库里。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    CapsuleScrollMarker()
                    ForEach(Array(entries.enumerated()), id: \.element.id) { queueIndex, entry in
                        if let track = entry.record.track {
                            songRow(track: track, queueIndex: queueIndex, entry: entry)
                                .listRowInsets(EdgeInsets())
                                .listRowSeparator(.hidden)
                                .listRowBackground(scheme.appSurface)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .coordinateSpace(name: CapsuleScrollTracking.coordinateSpace)
                .onPreferenceChange(CapsuleScrollOffsetPreferenceKey.self, perform: reportScrollOffset)
                .onDisappear(perform: finishScrollTracking)
            }
        }
        .background(scheme.appSurface.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: $showingPlaylists) {
            PlaylistsView(playlists: playlists)
        }
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .libraryView:
                LibraryViewSheet(selection: $selectedPlaylistID)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            case let .addToPlaylist(track):
                AddToPlaylistSheet(track: track)
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
        .onChange(of: isActive) { _, _ in finishScrollTracking() }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Button {
                presentedSheet = .libraryView
            } label: {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 22, weight: .semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(scheme.onSurface)
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("library-view-menu-button")

            iconButton(systemName: "music.note.list", label: "歌单") {
                showingPlaylists = true
            }
            iconButton(systemName: "shuffle", label: "随机播放") {
                playShuffled()
            }
            Spacer(minLength: 0)
            Menu {
                Button("搜索", systemImage: "magnifyingglass") { isSearching = true }
                Button("下载历史", systemImage: "arrow.down.circle") {
                    toastCenter.show("下载历史即将推出")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 21, weight: .medium))
                    .foregroundStyle(scheme.onSurfaceVariant)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("更多")
            .accessibilityIdentifier("library-more-button")
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
            TextField("搜索歌曲、歌手或专辑", text: $searchQuery)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("library-search-field")
            Button {
                searchQuery = ""
                isSearching = false
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭搜索")
        }
        .foregroundStyle(scheme.onSurfaceVariant)
        .padding(.horizontal, 16)
        .frame(minHeight: 44)
    }

    private var countRow: some View {
        Text("\(tracks.count) 首歌曲")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(scheme.onSurfaceVariant)
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .padding(.horizontal, 16)
            .accessibilityIdentifier("library-track-count")
    }

    private func iconButton(systemName: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(scheme.onSurfaceVariant)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(label == "歌单" ? "library-playlists-button" : "library-shuffle-button")
    }

    private func songRow(track: Track, queueIndex: Int, entry: Entry) -> some View {
        SongRow(
            track: track,
            isCurrent: playbackService.queue.current?.musicID == track.musicID,
            isPlaying: playbackService.state == .playing,
            onPlay: { Task { await playbackService.replaceQueue(tracks, startingAt: queueIndex) } },
            onAction: { presentedSheet = .addToPlaylist(track) }
        )
        .padding(.horizontal, 14)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if let selectedPlaylist, let index = entry.playlistIndex {
                Button("移出歌单", systemImage: "text.badge.minus", role: .destructive) {
                    perform { try LibraryStore(context: modelContext).removeItem(at: index, from: selectedPlaylist) }
                    toastCenter.show("已移出歌单")
                }
            } else {
                Button("删除", systemImage: "trash", role: .destructive) {
                    // 偏离规格：现有 LibraryStore 没有删除曲目契约，界面不绕过存储层直接删模型。
                    toastCenter.show("当前版本暂不支持从曲库删除")
                }
            }
            Button("歌单", systemImage: "text.badge.plus") {
                presentedSheet = .addToPlaylist(track)
            }
            .tint(scheme.secondary)
        }
    }

    private func playShuffled() {
        let shuffled = tracks.shuffled()
        guard !shuffled.isEmpty else { return }
        Task { await playbackService.replaceQueue(shuffled) }
        toastCenter.show("随机播放")
    }

    private func perform(_ operation: () throws -> Void) {
        do { try operation() } catch { errorMessage = error.localizedDescription }
    }

    private func reportScrollOffset(_ markerY: CGFloat) {
        guard isActive else {
            lastScrollMarkerY = nil
            return
        }
        if let lastScrollMarkerY { capsuleScrollReporter.update(lastScrollMarkerY - markerY) }
        self.lastScrollMarkerY = markerY
        scrollSettleTask?.cancel()
        scrollSettleTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            capsuleScrollReporter.settle()
        }
    }

    private func finishScrollTracking() {
        scrollSettleTask?.cancel()
        scrollSettleTask = nil
        lastScrollMarkerY = nil
        if isActive { capsuleScrollReporter.settle() }
    }
}

private struct LibraryViewSheet: View {
    @Binding var selection: UUID?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.m3Scheme) private var scheme
    @Query(filter: #Predicate<Playlist> { !$0.isSystem }, sort: \Playlist.sortIndex)
    private var playlists: [Playlist]
    @Query private var tracks: [TrackRecord]

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "曲库视图")
            ScrollView {
                LazyVStack(spacing: 4) {
                    option(title: "全部歌曲", subtitle: "\(tracks.count) 首", id: nil)
                    ForEach(playlists) { playlist in
                        option(title: playlist.name, subtitle: "\(playlist.items.count) 首", id: playlist.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .background(scheme.surfaceContainerLow.ignoresSafeArea())
    }

    private func option(title: String, subtitle: String, id: UUID?) -> some View {
        let isSelected = selection == id
        return Button {
            selection = id
            dismiss()
        } label: {
            HStack(spacing: 16) {
                Image(systemName: id == nil ? "music.note" : "music.note.list")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(scheme.onSecondaryContainer)
                    .frame(width: 36, height: 36)
                    .background(scheme.secondaryContainer, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(scheme.onSurface)
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(scheme.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(scheme.onSecondaryContainer)
                }
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 64)
            .background(
                isSelected ? scheme.secondaryContainer.opacity(0.72) : scheme.surfaceContainer,
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

struct PlaylistsView: View {
    let playlists: [Playlist]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.m3Scheme) private var scheme

    @State private var showingCreate = false
    @State private var newName = ""
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if playlists.isEmpty {
                ContentUnavailableView(
                    "还没有歌单",
                    systemImage: "music.note.list",
                    description: Text("新建歌单后，可以从搜索结果或播放器加入曲目。")
                )
            } else {
                List(playlists) { playlist in
                    NavigationLink {
                        PlaylistDetailView(playlist: playlist)
                    } label: {
                        HStack(spacing: 12) {
                            PlayerArtwork(
                                track: playlist.items.sorted { $0.sortIndex < $1.sortIndex }.first?.track.track,
                                size: 52
                            )
                            VStack(alignment: .leading, spacing: 4) {
                                Text(playlist.name)
                                    .font(.system(size: 14, weight: .medium))
                                Text("\(playlist.items.count) 首")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(scheme.onSurfaceVariant)
                            }
                        }
                        .frame(minHeight: 68)
                    }
                    .listRowBackground(scheme.appSurface)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(scheme.appSurface.ignoresSafeArea())
        .navigationTitle("我的歌单")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingCreate = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("新建歌单")
                    .accessibilityIdentifier("playlist-create-button")
            }
        }
        .alert("新建歌单", isPresented: $showingCreate) {
            TextField("歌单名称", text: $newName)
            Button("取消", role: .cancel) { newName = "" }
            Button("创建") {
                perform { _ = try LibraryStore(context: modelContext).createPlaylist(named: newName) }
                newName = ""
            }
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

    private func perform(_ operation: () throws -> Void) {
        do { try operation() } catch { errorMessage = error.localizedDescription }
    }
}
