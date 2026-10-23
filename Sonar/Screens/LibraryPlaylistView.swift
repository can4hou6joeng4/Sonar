import SwiftData
import SwiftUI

/// 资料库 Tab 的根页面：直接就是唯一歌单的详情，不再有中间概览页。
struct LibraryPlaylistView: View {
    let onOpenSettings: () -> Void

    @Environment(\.m3Scheme) private var scheme
    @Query(sort: \Playlist.sortIndex) private var playlists: [Playlist]

    private var personalPlaylist: Playlist? {
        playlists.first { $0.isPrimaryPersonal && !$0.isArchived && !$0.isSystem && $0.kind == .music }
    }

    var body: some View {
        Group {
            if let personalPlaylist {
                PlaylistDetailView(
                    playlist: personalPlaylist,
                    showsBackButton: false,
                    onOpenSettings: onOpenSettings
                )
            } else {
                ProgressView("正在准备歌单…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(scheme.appSurface.ignoresSafeArea())
            }
        }
    }
}
