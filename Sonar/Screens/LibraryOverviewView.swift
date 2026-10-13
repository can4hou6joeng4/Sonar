import SwiftData
import SwiftUI

struct LibraryOverviewView: View {
    let onOpenSettings: () -> Void
    let onOpenCollection: () -> Void
    @Environment(\.m3Scheme) private var scheme
    @Query(sort: \Playlist.sortIndex) private var playlists: [Playlist]
    @Query private var records: [TrackRecord]

    private var savedPlaylists: [Playlist] {
        playlists.filter { !$0.isArchived && !$0.isSystem && !$0.isPrimaryPersonal && $0.kind == .music }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("留住喜欢的声音")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(scheme.onSurfaceVariant)
                        Text("资料库")
                            .font(.system(size: 34, weight: .bold))
                    }
                    Spacer()
                    Button(action: onOpenSettings) {
                        Image(systemName: "gearshape").font(.system(size: 21)).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("设置")
                    .accessibilityIdentifier("library-settings-button")
                }

                VStack(spacing: 12) {
                    Button(action: onOpenCollection) {
                        libraryRow(title: "我的收藏", subtitle: "\(personalCount) 首歌曲", symbol: "heart.fill", artwork: personalPlaylist?.orderedItems.first?.track.track)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("library-favorites")

                    if let recent = playlists.first(where: { $0.id == LibraryStore.recentPlaylistID }) {
                        NavigationLink {
                            PlaylistDetailView(playlist: recent)
                        } label: {
                            libraryRow(title: "最近播放", subtitle: "\(recent.items.count) 首歌曲", symbol: "clock", artwork: recent.orderedItems.first?.track.track)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("library-recent")
                    }

                    NavigationLink { LocalSongsView() } label: {
                        libraryRow(title: "所有歌曲", subtitle: "\(records.count) 首已保存的歌曲信息", symbol: "music.note.list", artwork: nil)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("library-all-songs")
                }

                if !savedPlaylists.isEmpty {
                    Text("我的歌单").font(.system(size: 20, weight: .bold))
                    VStack(spacing: 12) {
                        ForEach(savedPlaylists) { playlist in
                            NavigationLink { PlaylistDetailView(playlist: playlist) } label: {
                                libraryRow(title: playlist.name, subtitle: "\(playlist.items.count) 首歌曲", symbol: "square.stack", artwork: playlist.orderedItems.first?.track.track)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Button(action: onOpenSettings) {
                    HStack(spacing: 14) {
                        Image(systemName: "square.and.arrow.down").font(.system(size: 22))
                        VStack(alignment: .leading, spacing: 5) {
                            Text("带上你的歌单").font(.system(size: 16, weight: .semibold))
                            Text("导入网易云歌单，或备份自己的收藏")
                                .font(.system(size: 12)).foregroundStyle(scheme.onSurfaceVariant)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .padding(18)
                    .background(scheme.surfaceContainer, in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("library-import-button")
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 24)
        }
        .foregroundStyle(scheme.onSurface)
        .background(scheme.appSurface.ignoresSafeArea())
        .scrollIndicators(.hidden)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var personalPlaylist: Playlist? {
        playlists.first { $0.isPrimaryPersonal && !$0.isArchived && !$0.isSystem && $0.kind == .music }
    }
    private var personalCount: Int { personalPlaylist?.items.count ?? 0 }

    private func libraryRow(title: String, subtitle: String, symbol: String, artwork: Track?) -> some View {
        HStack(spacing: 15) {
            if let artwork {
                PlayerArtwork(track: artwork, size: 62, cornerRadius: 12)
            } else {
                Image(systemName: symbol).font(.system(size: 23))
                    .frame(width: 62, height: 62)
                    .background(scheme.primaryContainer.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 17, weight: .semibold))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(scheme.onSurfaceVariant)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 12)).foregroundStyle(scheme.onSurfaceVariant)
        }
        .padding(14)
        .background(scheme.surfaceContainer, in: RoundedRectangle(cornerRadius: 18))
        .contentShape(Rectangle())
    }
}
