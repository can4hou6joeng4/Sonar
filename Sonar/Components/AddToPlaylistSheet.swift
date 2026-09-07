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
            !$0.isSystem && $0.kindRaw == "music" && $0.isPrimaryPersonal && !$0.isArchived
        },
        sort: \Playlist.sortIndex
    )
    private var playlists: [Playlist]

    @State private var errorMessage: String?

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
                        ForEach(playlists) { playlist in
                            Button {
                                add(to: playlist)
                            } label: {
                                HStack(spacing: 16) {
                                    PlayerArtwork(track: firstTrack(in: playlist), size: 36)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(playlist.isPrimaryPersonal ? "我喜欢的音乐" : playlist.name)
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
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
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
