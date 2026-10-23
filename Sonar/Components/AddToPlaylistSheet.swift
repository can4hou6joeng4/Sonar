import SwiftData
import SwiftUI

struct AddToPlaylistSheet: View {
    let track: Track

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ConfirmationCenter.self) private var confirmationCenter
    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.m3Scheme) private var scheme
    @Query(
        filter: #Predicate<Playlist> {
            !$0.isSystem && $0.kindRaw == "music" && !$0.isArchived
        },
        sort: \Playlist.sortIndex
    )
    private var playlists: [Playlist]

    @State private var errorMessage: String?
    @State private var isCreating = false
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "收藏到歌单", subtitle: track.title)
                .accessibilityIdentifier("add-to-playlist-sheet")

            if playlists.isEmpty {
                ContentUnavailableView(
                    "歌单暂不可用",
                    systemImage: "music.note.list",
                    description: Text("个人歌单正在准备，请稍后重试。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        Button {
                            newName = ""
                            isCreating = true
                        } label: {
                            HStack(spacing: 16) {
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(scheme.primary)
                                    .frame(width: 36, height: 36)
                                    .background(scheme.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                Text("新建歌单并添加")
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(scheme.onSurface)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 64)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("add-to-playlist-create")

                        ForEach(playlists) { playlist in
                            Button {
                                add(to: playlist)
                            } label: {
                                HStack(spacing: 16) {
                                    PlayerArtwork(track: firstTrack(in: playlist), size: 36)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(playlist.name)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(scheme.onSurface)
                                        Text("\(playlist.items.count) 首")
                                            .font(.caption)
                                            .foregroundStyle(scheme.onSurfaceVariant)
                                    }
                                    Spacer(minLength: 0)
                                    if containsTrack(playlist) {
                                        Text("已在其中")
                                            .font(.caption)
                                            .foregroundStyle(scheme.onSurfaceVariant)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 64)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("add-to-playlist-\(playlist.id)")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
        }
        .foregroundStyle(scheme.onSurface)
        .background(scheme.surfaceContainerLow.ignoresSafeArea())
        .onDisappear {
            Task { @MainActor in
                await confirmationCenter.presentPendingAfterDismissal()
            }
        }
        .task {
            guard playlists.isEmpty else { return }
            do {
                _ = try LibraryStore(context: modelContext).ensurePersonalPlaylist()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .alert("新建歌单", isPresented: $isCreating) {
            TextField("歌单名称", text: $newName)
            Button("取消", role: .cancel) { newName = "" }
            Button("创建并添加") { createAndAdd() }
        } message: {
            Text("会立刻把《\(track.title)》放进新歌单。")
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

    private func createAndAdd() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        newName = ""
        guard !name.isEmpty else { return }
        do {
            let store = LibraryStore(context: modelContext)
            let playlist = try store.createPlaylist(named: name)
            _ = try store.add(track, to: playlist)
            confirmationCenter.enqueueAfterPresentationDismissal(
                title: "已加入「\(name)」",
                message: "《\(track.title)》已收藏到新歌单。",
                acknowledgment: "知道了"
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func firstTrack(in playlist: Playlist) -> Track? {
        playlist.orderedItems.first?.track.track
    }

    private func containsTrack(_ playlist: Playlist) -> Bool {
        playlist.items.contains { $0.track.musicId == track.musicID }
    }

    private func add(to playlist: Playlist) {
        if containsTrack(playlist) {
            confirmationCenter.enqueueAfterPresentationDismissal(
                title: "已经收藏",
                message: "「\(track.title)」已在「\(playlist.name)」中。"
            )
            dismiss()
            return
        }
        do {
            _ = try LibraryStore(context: modelContext).add(track, to: playlist)
            playbackService.onTrackAddedToPlaylist(track, playlistID: playlist.id)
            confirmationCenter.enqueueAfterPresentationDismissal(
                title: "收藏成功",
                message: "已将「\(track.title)」收藏到「\(playlist.name)」。",
                acknowledgment: "知道了"
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SheetHeader: View {
    let title: String
    var subtitle: String?

    @Environment(\.m3Scheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.title2.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(scheme.onSurfaceVariant)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
}
