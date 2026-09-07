import SwiftData
import SwiftUI

struct SongsView: View {
    let isActive: Bool
    let onOpenSettings: () -> Void
    let onSettingsDragChanged: (DragGesture.Value) -> Void
    let onSettingsDragEnded: (DragGesture.Value) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.m3Scheme) private var scheme
    @Query(sort: \Playlist.sortIndex) private var allPlaylists: [Playlist]

    @State private var errorMessage: String?
    @State private var isProvisioningPersonalPlaylist = false

    private var personalPlaylist: Playlist? {
        allPlaylists.first {
            $0.isPrimaryPersonal && !$0.isArchived && !$0.isSystem && $0.kind == .music
        }
    }

    init(
        isActive: Bool,
        onOpenSettings: @escaping () -> Void = {},
        onSettingsDragChanged: @escaping (DragGesture.Value) -> Void = { _ in },
        onSettingsDragEnded: @escaping (DragGesture.Value) -> Void = { _ in }
    ) {
        self.isActive = isActive
        self.onOpenSettings = onOpenSettings
        self.onSettingsDragChanged = onSettingsDragChanged
        self.onSettingsDragEnded = onSettingsDragEnded
    }

    var body: some View {
        Group {
            if let playlist = personalPlaylist {
                PlaylistDetailView(playlist: playlist, onBack: { dismiss() })
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("歌单暂不可用", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重试", action: provisionPersonalPlaylist)
                }
            } else {
                ProgressView("正在打开歌单…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(scheme.appSurface.ignoresSafeArea())
            }
        }
        .task { provisionPersonalPlaylist() }
    }

    private func provisionPersonalPlaylist() {
        guard !isProvisioningPersonalPlaylist else { return }
        isProvisioningPersonalPlaylist = true
        defer { isProvisioningPersonalPlaylist = false }
        do {
            _ = try LibraryStore(context: modelContext).ensurePersonalPlaylist()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct LocalSongsView: View {
    private enum PresentedSheet: Identifiable {
        case actions(Track)

        var id: String {
            switch self {
            case let .actions(track): "actions-\(track.musicID)"
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
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("清空")
                }
            }
            .font(.system(size: 15))
            .foregroundStyle(scheme.onSurfaceVariant)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
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
                                onPlay: { Task { await playbackService.replaceQueue([track]) } },
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
                    onAddToQueue: { addToQueue(track) },
                    onCollect: {
                        presentedSheet = nil
                        PersonalPlaylistCollectionFeedback.collect(
                            track,
                            context: modelContext,
                            toastCenter: toastCenter,
                            playbackService: playbackService
                        )
                    },
                    onDelete: { deleteTrack(track) }
                )
                .presentationDetents([.height(264)])
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

    private func addToQueue(_ track: Track) {
        presentedSheet = nil
        Task {
            let added = await playbackService.enqueue(track)
            toastCenter.show(added ? "已加入待播放" : "歌曲已在待播放中")
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
    let onAddToQueue: () -> Void
    let onCollect: () -> Void
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

            actionButton("加入待播放", systemImage: "text.badge.plus") {
                dismiss()
                onAddToQueue()
            }
            actionButton("收藏到歌单", systemImage: "music.note.list") {
                dismiss()
                onCollect()
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
