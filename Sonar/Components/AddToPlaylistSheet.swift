import SwiftData
import SwiftUI

struct AddToPlaylistSheet: View {
    let track: Track

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ToastCenter.self) private var toastCenter
    @Environment(\.m3Scheme) private var scheme
    @Query(filter: #Predicate<Playlist> { !$0.isSystem }, sort: \Playlist.sortIndex)
    private var playlists: [Playlist]

    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "加入歌单", subtitle: track.title)
                .accessibilityIdentifier("add-to-playlist-sheet")

            if playlists.isEmpty {
                ContentUnavailableView(
                    "还没有歌单",
                    systemImage: "music.note.list",
                    description: Text("请先在歌曲页创建歌单。")
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
                                        Text(playlist.name)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(scheme.onSurface)
                                        Text("\(playlist.items.count) 首")
                                            .font(.system(size: 12.5))
                                            .foregroundStyle(scheme.onSurfaceVariant)
                                    }
                                    Spacer(minLength: 0)
                                    if containsTrack(playlist) {
                                        Text("已在其中")
                                            .font(.system(size: 12.5))
                                            .foregroundStyle(scheme.onSurfaceVariant)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 64)
                                .background(scheme.surfaceContainer, in: RoundedRectangle(cornerRadius: 20))
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
        playlist.items.sorted { $0.sortIndex < $1.sortIndex }.first?.track.track
    }

    private func containsTrack(_ playlist: Playlist) -> Bool {
        playlist.items.contains { $0.track.musicId == track.musicID }
    }

    private func add(to playlist: Playlist) {
        if containsTrack(playlist) {
            toastCenter.show("已经在「\(playlist.name)」里了")
            dismiss()
            return
        }
        do {
            _ = try LibraryStore(context: modelContext).add(track, to: playlist)
            toastCenter.show("已加入「\(playlist.name)」")
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
                    .font(.system(size: 22, weight: .semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12.5, weight: .medium))
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
