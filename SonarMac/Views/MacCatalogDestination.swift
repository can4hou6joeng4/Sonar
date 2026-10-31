import Foundation

/// 面板内的目录导航目标：歌手、专辑与歌单都复用同一套解析与播放路径。
enum MacCatalogDestination {
    case artist(ArtistSummary)
    case album(AlbumSummary)
    case playlist(PlaylistSummary)
}
