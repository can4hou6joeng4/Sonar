package cn.bobochang.sonar.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ArrowBack
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Shuffle
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cn.bobochang.sonar.data.model.AlbumSummary
import cn.bobochang.sonar.data.model.ArtistSummary
import cn.bobochang.sonar.data.model.PlaylistSummary
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.di.AppContainer
import cn.bobochang.sonar.playback.PlaybackMode
import cn.bobochang.sonar.playback.PlayerUiState
import cn.bobochang.sonar.ui.components.LocalToast
import cn.bobochang.sonar.ui.components.RemoteArtwork
import cn.bobochang.sonar.ui.components.SkeletonSongList
import cn.bobochang.sonar.ui.components.SongLeading
import cn.bobochang.sonar.ui.components.SongRow
import cn.bobochang.sonar.ui.components.SongTrailing
import cn.bobochang.sonar.ui.theme.LocalSonarPalette
import cn.bobochang.sonar.ui.theme.bouncePress
import kotlinx.coroutines.launch

/** 本地歌单 / 我的收藏：对应 iOS `PlaylistDetailView`。 */
@Composable
fun PlaylistDetailScreen(
    container: AppContainer,
    playerState: PlayerUiState,
    playlistId: String?,
    bottomPadding: Dp,
    onBack: () -> Unit,
    onSongAction: (Track) -> Unit,
) {
    val palette = LocalSonarPalette.current
    val toast = LocalToast.current
    val scope = rememberCoroutineScope()
    val favorites by container.library.observeFavorites().collectAsState(initial = emptyList())
    val playlists by container.library.observePlaylists().collectAsState(initial = emptyList())
    val playlistTracks by remember(playlistId) {
        if (playlistId == null) kotlinx.coroutines.flow.flowOf(emptyList()) else container.library.observePlaylistTracks(playlistId)
    }.collectAsState(initial = emptyList())
    val playlist = playlists.firstOrNull { it.id == playlistId }
    val tracks = if (playlistId == null) favorites else playlistTracks
    val title = if (playlistId == null) "我的收藏" else playlist?.name ?: "歌单"
    var selecting by remember { mutableStateOf(false) }
    val selected = remember { mutableStateListOf<String>() }
    val statusTop = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    val durationText = remember(tracks) {
        val total = tracks.sumOf { it.durationMs ?: 0L }
        if (total <= 0L) null else formatDuration(total)
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.background)
            .padding(top = statusTop),
    ) {
        DetailNavBar(
            title = "",
            onBack = onBack,
            trailing = if (tracks.isNotEmpty()) {
                {
                    Text(
                        text = if (selecting) "取消" else "选择",
                        color = palette.ink,
                        fontSize = 15.sp,
                        modifier = Modifier.clickable {
                            selecting = !selecting
                            selected.clear()
                        }.padding(12.dp),
                    )
                }
            } else null,
        )
        if (selecting) {
            SelectionBar(
                allSelected = selected.size == tracks.size,
                count = selected.size,
                canRemove = playlistId != null,
                onToggleAll = {
                    if (selected.size == tracks.size) selected.clear()
                    else {
                        selected.clear()
                        selected.addAll(tracks.map { it.musicId })
                    }
                },
                onEnqueue = {
                    val values = tracks.filter { selected.contains(it.musicId) }
                    scope.launch {
                        var added = 0
                        values.forEach { track ->
                            runCatching {
                                container.playerConnection.enqueue(track, container.settings.snapshot().quality)
                                added++
                            }
                        }
                        toast.show("已加入待播放 $added 首")
                        selecting = false
                        selected.clear()
                    }
                },
                onRemove = if (playlistId != null) {
                    {
                        scope.launch {
                            tracks.filter { selected.contains(it.musicId) }.forEach { track ->
                                container.library.removeFromPlaylist(playlistId, track.musicId)
                            }
                            toast.show("已移出 ${selected.size} 首")
                            selecting = false
                            selected.clear()
                        }
                    }
                } else null,
            )
        }

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(bottom = bottomPadding + 20.dp),
        ) {
            item(key = "header") {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp)
                        .padding(top = 4.dp, bottom = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text(
                        text = title,
                        color = palette.ink,
                        fontSize = 28.sp,
                        fontWeight = FontWeight.Bold,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text("${tracks.size} 首歌曲", color = palette.secondaryInk, fontSize = 14.sp, fontWeight = FontWeight.Medium)
                        if (durationText != null) {
                            Text("·", color = palette.secondaryInk, fontSize = 14.sp)
                            Text(durationText, color = palette.secondaryInk, fontSize = 14.sp, fontWeight = FontWeight.Medium)
                        }
                    }
                }
            }
            item(key = "actions") {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp)
                        .padding(bottom = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    DetailActionButton(
                        title = "播放全部",
                        badge = tracks.size.takeIf { it > 0 }?.toString(),
                        icon = Icons.Rounded.PlayArrow,
                        primary = true,
                        enabled = tracks.any { it.source.isEnabled },
                        modifier = Modifier.weight(1f),
                    ) {
                        if (tracks.isNotEmpty()) {
                            scope.launch {
                                container.playerConnection.setPlaybackMode(PlaybackMode.SEQUENCE)
                                container.playerConnection.playTracks(tracks, 0, container.settings.snapshot().quality)
                            }
                        }
                    }
                    DetailActionButton(
                        title = "随机播放",
                        icon = Icons.Rounded.Shuffle,
                        primary = false,
                        enabled = tracks.any { it.source.isEnabled },
                        modifier = Modifier.weight(1f),
                    ) {
                        if (tracks.isNotEmpty()) {
                            scope.launch {
                                container.playerConnection.setPlaybackMode(PlaybackMode.SHUFFLE)
                                container.playerConnection.playTracks(
                                    tracks.shuffled(),
                                    0,
                                    container.settings.snapshot().quality,
                                )
                            }
                        }
                    }
                }
            }
            if (tracks.isEmpty()) {
                item(key = "empty") {
                    EmptyDetail("这个歌单还没有歌曲", "在搜索结果或歌手页面选择“收藏到歌单”，歌曲会保存在这里")
                }
            } else {
                itemsIndexed(tracks, key = { _, track -> track.musicId }) { index, track ->
                    SongRow(
                        track = track,
                        leading = SongLeading.Index(index + 1),
                        trailing = if (selecting) {
                            SongTrailing.CollectionStatus(selected.contains(track.musicId))
                        } else {
                            SongTrailing.More
                        },
                        showAlbum = false,
                        showDivider = index < tracks.lastIndex,
                        isSelected = selected.contains(track.musicId),
                        isCurrent = playerState.track?.musicId == track.musicId,
                        isPlaying = playerState.isPlaying,
                        onPlay = {
                            if (selecting) {
                                if (selected.contains(track.musicId)) selected.remove(track.musicId)
                                else selected.add(track.musicId)
                            } else {
                                scope.launch {
                                    container.playerConnection.setPlaybackMode(PlaybackMode.SEQUENCE)
                                    container.playerConnection.playTracks(tracks, index, container.settings.snapshot().quality)
                                }
                            }
                        },
                        onAction = {
                            if (selecting) {
                                if (selected.contains(track.musicId)) selected.remove(track.musicId)
                                else selected.add(track.musicId)
                            } else {
                                onSongAction(track)
                            }
                        },
                    )
                }
            }
        }
    }
}

/** 网易云歌单：对应 iOS `RemotePlaylistDetailView`（搜索结果的歌单页）。 */
@Composable
fun RemotePlaylistScreen(
    container: AppContainer,
    playerState: PlayerUiState,
    playlist: PlaylistSummary,
    bottomPadding: Dp,
    onBack: () -> Unit,
    onSongAction: (Track) -> Unit,
) {
    val palette = LocalSonarPalette.current
    val scope = rememberCoroutineScope()
    var tracks by remember(playlist.id) { mutableStateOf<List<Track>>(emptyList()) }
    var total by remember(playlist.id) { mutableStateOf(playlist.total) }
    var loading by remember(playlist.id) { mutableStateOf(true) }
    var error by remember(playlist.id) { mutableStateOf<String?>(null) }
    val statusTop = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()

    LaunchedEffect(playlist.id) {
        loading = true
        error = null
        runCatching { container.netEase.playlistDetail(playlist.id) }
            .onSuccess {
                tracks = it.tracks
                total = it.total
            }
            .onFailure { error = it.message ?: "加载失败" }
        loading = false
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.background)
            .padding(top = statusTop),
    ) {
        DetailNavBar(title = "网易云歌单", onBack = onBack)
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(bottom = bottomPadding + 20.dp),
        ) {
            item(key = "header") {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(16.dp),
                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    RemoteArtwork(url = playlist.imageUrl, size = 88.dp, cornerRadius = 10.dp)
                    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(
                            text = playlist.name,
                            color = palette.ink,
                            fontSize = 20.sp,
                            fontWeight = FontWeight.Bold,
                            maxLines = 3,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Text(
                            text = playlist.author.ifBlank { "网易云音乐" },
                            color = palette.secondaryInk,
                            fontSize = 15.sp,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                        (total ?: 0).takeIf { it > 0 }?.let {
                            Text("$it 首歌曲", color = palette.secondaryInk, fontSize = 12.sp)
                        }
                    }
                }
            }
            when {
                loading && tracks.isEmpty() -> item(key = "loading") {
                    LoadingRow("正在加载歌单…")
                }

                error != null && tracks.isEmpty() -> item(key = "error") {
                    EmptyDetail("歌单暂不可用", error ?: "请稍后重试")
                }

                tracks.isNotEmpty() -> {
                    item(key = "play-all") {
                        WidePlayButton("播放全部") {
                            scope.launch {
                                container.playerConnection.setPlaybackMode(PlaybackMode.SEQUENCE)
                                container.playerConnection.playTracks(tracks, 0, container.settings.snapshot().quality)
                            }
                        }
                    }
                    itemsIndexed(tracks, key = { _, track -> track.musicId }) { index, track ->
                        SongRow(
                            track = track,
                            trailing = SongTrailing.More,
                            showDivider = index < tracks.lastIndex,
                            isCurrent = playerState.track?.musicId == track.musicId,
                            isPlaying = playerState.isPlaying,
                            onPlay = {
                                scope.launch {
                                    container.playerConnection.setPlaybackMode(PlaybackMode.SEQUENCE)
                                    container.playerConnection.playTracks(tracks, index, container.settings.snapshot().quality)
                                }
                            },
                            onAction = { onSongAction(track) },
                        )
                    }
                }
            }
        }
    }
}

private enum class ArtistTab(val label: String) {
    POPULAR("热门"),
    LATEST("最新"),
    ALBUMS("专辑"),
}

/** 歌手页：对应 iOS `ArtistDetailView`（热门 / 最新 / 专辑 三段内容）。 */
@Composable
fun ArtistDetailScreen(
    container: AppContainer,
    playerState: PlayerUiState,
    artist: ArtistSummary,
    bottomPadding: Dp,
    onBack: () -> Unit,
    onSongAction: (Track) -> Unit,
    onOpenAlbum: (AlbumSummary) -> Unit,
) {
    val palette = LocalSonarPalette.current
    val scope = rememberCoroutineScope()
    var tab by remember(artist.id) { mutableStateOf(ArtistTab.POPULAR) }
    var popular by remember(artist.id) { mutableStateOf<List<Track>>(emptyList()) }
    var popularLoading by remember(artist.id) { mutableStateOf(true) }
    var popularError by remember(artist.id) { mutableStateOf<String?>(null) }
    var albums by remember(artist.id) { mutableStateOf<List<AlbumSummary>?>(null) }
    var latestAlbums by remember(artist.id) { mutableStateOf<List<AlbumSummary>?>(null) }
    var latestTracks by remember(artist.id) { mutableStateOf<List<Track>>(emptyList()) }
    var latestError by remember(artist.id) { mutableStateOf<String?>(null) }
    var tabLoading by remember(artist.id) { mutableStateOf(false) }
    val statusTop = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()

    LaunchedEffect(artist.id) {
        popularLoading = true
        popularError = null
        runCatching { container.netEase.artist(artist.id) }
            .onSuccess { popular = dedupe(it.second) }
            .onFailure { popularError = it.message ?: "加载失败" }
        popularLoading = false
    }

    LaunchedEffect(artist.id, tab) {
        when (tab) {
            ArtistTab.LATEST -> if (latestAlbums == null) {
                tabLoading = true
                latestError = null
                runCatching {
                    val newest = container.netEase.artistAlbums(artist.id)
                        .sortedByDescending { it.releaseDate ?: "" }
                        .take(6)
                    val tracks = buildList {
                        newest.take(3).forEach { album ->
                            runCatching { container.netEase.album(album.id).second }
                                .onSuccess { addAll(it) }
                        }
                    }
                    newest to dedupe(tracks)
                }.onSuccess { (newest, tracks) ->
                    latestAlbums = newest
                    latestTracks = tracks
                }.onFailure { latestError = it.message ?: "加载失败" }
                tabLoading = false
            }

            ArtistTab.ALBUMS -> if (albums == null) {
                tabLoading = true
                latestError = null
                runCatching {
                    container.netEase.artistAlbums(artist.id)
                        .sortedByDescending { it.releaseDate ?: "" }
                }.onSuccess { albums = it }
                    .onFailure { latestError = it.message ?: "加载失败" }
                tabLoading = false
            }

            ArtistTab.POPULAR -> Unit
        }
    }

    fun play(track: Track) {
        scope.launch {
            container.playerConnection.setPlaybackMode(PlaybackMode.SEQUENCE)
            container.playerConnection.playTracks(listOf(track), 0, container.settings.snapshot().quality)
        }
    }

    val metadata = buildList {
        artist.songCount?.takeIf { it > 0 }?.let { add("$it 首歌曲") }
        artist.albumCount?.takeIf { it > 0 }?.let { add("$it 张专辑") }
    }.joinToString(" · ")

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.background)
            .padding(top = statusTop),
    ) {
        DetailNavBar(title = artist.name, onBack = onBack)
        Row(
            modifier = Modifier.fillMaxWidth().padding(16.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            RemoteArtwork(url = artist.imageUrl, size = 76.dp, cornerRadius = 38.dp)
            Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                Text(
                    text = artist.name,
                    color = palette.ink,
                    fontSize = 22.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                if (metadata.isNotBlank()) {
                    Text(metadata, color = palette.secondaryInk, fontSize = 12.sp)
                }
            }
        }
        SegmentedTabs(
            options = ArtistTab.entries.map { it.label },
            selectedIndex = tab.ordinal,
            onSelect = { tab = ArtistTab.entries[it] },
            modifier = Modifier.padding(horizontal = 16.dp).padding(bottom = 8.dp),
        )
        when (tab) {
            ArtistTab.POPULAR -> LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(bottom = bottomPadding + 20.dp),
            ) {
                when {
                    popularLoading && popular.isEmpty() -> item { SkeletonSongList(rows = 6, showsCover = false) }
                    popularError != null && popular.isEmpty() -> item { EmptyDetail("歌曲加载失败", popularError ?: "请稍后重试") }
                    popular.isEmpty() -> item { EmptyDetail("暂无歌曲", "这位歌手暂时没有可播放的歌曲") }
                    else -> itemsIndexed(popular, key = { _, track -> track.musicId }) { index, track ->
                        SongRow(
                            track = track,
                            leading = SongLeading.Index(index + 1),
                            trailing = SongTrailing.More,
                            showDivider = index < popular.lastIndex,
                            isCurrent = playerState.track?.musicId == track.musicId,
                            isPlaying = playerState.isPlaying,
                            onPlay = { play(track) },
                            onAction = { onSongAction(track) },
                        )
                    }
                }
            }

            ArtistTab.LATEST -> LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(bottom = bottomPadding + 20.dp),
            ) {
                when {
                    tabLoading && latestAlbums == null -> item {
                        SkeletonSongList(rows = 5, showsCover = false)
                    }

                    latestError != null && latestAlbums.isNullOrEmpty() -> item {
                        EmptyDetail("最新发行加载失败", latestError ?: "请稍后重试")
                    }

                    latestAlbums.isNullOrEmpty() -> item {
                        EmptyDetail("暂无最新发行", "这位歌手暂时没有新的专辑")
                    }

                    else -> {
                        item(key = "latest-title") { SectionHeading("最新专辑") }
                        items(latestAlbums.orEmpty(), key = { it.stableId }) { album ->
                            AlbumListRow(album = album) { onOpenAlbum(album) }
                        }
                        if (latestTracks.isNotEmpty()) {
                            item(key = "latest-tracks-title") { SectionHeading("新作歌曲", topPadding = 18.dp) }
                            itemsIndexed(latestTracks, key = { _, track -> track.musicId }) { index, track ->
                                SongRow(
                                    track = track,
                                    leading = SongLeading.Index(index + 1),
                                    trailing = SongTrailing.More,
                                    showDivider = index < latestTracks.lastIndex,
                                    isCurrent = playerState.track?.musicId == track.musicId,
                                    isPlaying = playerState.isPlaying,
                                    onPlay = { play(track) },
                                    onAction = { onSongAction(track) },
                                )
                            }
                        }
                    }
                }
            }

            ArtistTab.ALBUMS -> LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = PaddingValues(bottom = bottomPadding + 20.dp),
            ) {
                when {
                    tabLoading && albums == null -> item { SkeletonSongList(rows = 5, showsCover = false) }
                    latestError != null && albums.isNullOrEmpty() -> item {
                        EmptyDetail("专辑加载失败", latestError ?: "请稍后重试")
                    }
                    albums.isNullOrEmpty() -> item { EmptyDetail("暂无专辑", "这位歌手暂时没有专辑") }
                    else -> items(albums.orEmpty(), key = { it.stableId }) { album ->
                        AlbumListRow(album = album) { onOpenAlbum(album) }
                    }
                }
            }
        }
    }
}

/** 专辑页：对应 iOS `AlbumDetailView`。 */
@Composable
fun AlbumDetailScreen(
    container: AppContainer,
    playerState: PlayerUiState,
    album: AlbumSummary,
    bottomPadding: Dp,
    onBack: () -> Unit,
    onSongAction: (Track) -> Unit,
) {
    val palette = LocalSonarPalette.current
    val scope = rememberCoroutineScope()
    var detail by remember(album.id) { mutableStateOf<AlbumSummary?>(null) }
    var tracks by remember(album.id) { mutableStateOf<List<Track>>(emptyList()) }
    var loading by remember(album.id) { mutableStateOf(true) }
    var error by remember(album.id) { mutableStateOf<String?>(null) }
    val statusTop = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()

    LaunchedEffect(album.id) {
        loading = true
        error = null
        runCatching { container.netEase.album(album.id) }
            .onSuccess {
                detail = it.first
                tracks = dedupe(it.second)
            }
            .onFailure { error = it.message ?: "加载失败" }
        loading = false
    }

    val shown = detail ?: album
    val metadata = listOfNotNull(
        shown.releaseDate,
        shown.trackCount?.takeIf { it > 0 }?.let { "$it 首" },
        "网易云",
    ).joinToString(" · ")

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.background)
            .padding(top = statusTop),
    ) {
        DetailNavBar(title = shown.name, onBack = onBack)
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(bottom = bottomPadding + 20.dp),
        ) {
            item(key = "header") {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(16.dp),
                    horizontalArrangement = Arrangement.spacedBy(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    RemoteArtwork(url = shown.imageUrl, size = 112.dp, cornerRadius = 8.dp)
                    Column(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                        Text(
                            text = shown.name,
                            color = palette.ink,
                            fontSize = 17.sp,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 3,
                            overflow = TextOverflow.Ellipsis,
                        )
                        if (shown.artist.isNotBlank()) {
                            Text(
                                shown.artist,
                                color = palette.secondaryInk,
                                fontSize = 15.sp,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                        Text(metadata, color = palette.secondaryInk, fontSize = 12.sp, maxLines = 2)
                    }
                }
            }
            when {
                loading && tracks.isEmpty() -> item(key = "loading") {
                    SkeletonSongList(rows = 8, showsCover = false)
                }

                error != null && tracks.isEmpty() -> item(key = "error") {
                    EmptyDetail("专辑加载失败", error ?: "请稍后重试")
                }

                tracks.isEmpty() -> item(key = "empty") {
                    EmptyDetail("这张专辑暂无曲目", "稍后再来看看")
                }

                else -> itemsIndexed(tracks, key = { _, track -> track.musicId }) { index, track ->
                    SongRow(
                        track = track,
                        leading = SongLeading.Index(index + 1),
                        trailing = SongTrailing.More,
                        showAlbum = false,
                        showDivider = index < tracks.lastIndex,
                        isCurrent = playerState.track?.musicId == track.musicId,
                        isPlaying = playerState.isPlaying,
                        onPlay = {
                            scope.launch {
                                container.playerConnection.setPlaybackMode(PlaybackMode.SEQUENCE)
                                container.playerConnection.playTracks(listOf(track), 0, container.settings.snapshot().quality)
                            }
                        },
                        onAction = { onSongAction(track) },
                    )
                }
            }
        }
    }
}

@Composable
private fun DetailNavBar(
    title: String,
    onBack: () -> Unit,
    trailing: (@Composable () -> Unit)? = null,
) {
    val palette = LocalSonarPalette.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(44.dp)
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = Modifier.size(44.dp).clickable(onClick = onBack),
            contentAlignment = Alignment.CenterStart,
        ) {
            Icon(Icons.Rounded.ArrowBack, contentDescription = "返回", tint = palette.ink, modifier = Modifier.size(20.dp))
        }
        if (title.isNotBlank()) {
            Text(
                text = title,
                color = palette.ink,
                fontSize = 17.sp,
                fontWeight = FontWeight.Bold,
                textAlign = TextAlign.Center,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
        } else {
            Spacer(Modifier.weight(1f))
        }
        if (trailing != null) trailing() else Spacer(Modifier.size(44.dp))
    }
}

@Composable
private fun DetailActionButton(
    title: String,
    icon: ImageVector,
    primary: Boolean,
    enabled: Boolean,
    modifier: Modifier,
    badge: String? = null,
    onClick: () -> Unit,
) {
    val palette = LocalSonarPalette.current
    val interaction = remember { MutableInteractionSource() }
    Box(
        modifier = modifier
            .height(44.dp)
            .then(bouncePress(interaction, 0.96f, 0.9f, haptic = false))
            .clickable(interactionSource = interaction, indication = null, enabled = enabled, onClick = onClick),
        contentAlignment = Alignment.Center,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(40.dp)
                .background(if (primary) palette.accent else palette.elevated, RoundedCornerShape(8.dp)),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center,
        ) {
            val tint = if (primary) palette.onAccent else palette.ink
            Icon(icon, contentDescription = null, tint = tint.copy(alpha = if (enabled) 1f else 0.45f), modifier = Modifier.size(14.dp))
            Spacer(Modifier.size(6.dp))
            Text(
                text = title,
                color = tint.copy(alpha = if (enabled) 1f else 0.45f),
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
            )
            if (badge != null) {
                Spacer(Modifier.size(4.dp))
                Text(
                    text = "($badge)",
                    color = tint.copy(alpha = if (enabled) 0.85f else 0.45f),
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                )
            }
        }
    }
}

@Composable
private fun WidePlayButton(title: String, onClick: () -> Unit) {
    val palette = LocalSonarPalette.current
    val interaction = remember { MutableInteractionSource() }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .padding(bottom = 8.dp)
            .height(44.dp)
            .clip(RoundedCornerShape(8.dp))
            .background(palette.accent)
            .then(bouncePress(interaction, 0.96f, 0.9f, haptic = false))
            .clickable(interactionSource = interaction, indication = null, onClick = onClick),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        Icon(Icons.Rounded.PlayArrow, contentDescription = null, tint = palette.onAccent, modifier = Modifier.size(14.dp))
        Spacer(Modifier.size(6.dp))
        Text(title, color = palette.onAccent, fontSize = 14.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun SegmentedTabs(
    options: List<String>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalSonarPalette.current
    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(palette.inputFill, CircleShape)
            .padding(3.dp),
    ) {
        options.forEachIndexed { index, label ->
            val active = index == selectedIndex
            Box(
                modifier = Modifier
                    .weight(1f)
                    .height(32.dp)
                    .clip(CircleShape)
                    .background(if (active) palette.background else Color.Transparent)
                    .clickable { onSelect(index) },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = label,
                    color = palette.ink,
                    fontSize = 13.sp,
                    fontWeight = if (active) FontWeight.SemiBold else FontWeight.Normal,
                )
            }
        }
    }
}

@Composable
private fun SectionHeading(title: String, topPadding: Dp = 0.dp) {
    val palette = LocalSonarPalette.current
    Text(
        text = title,
        color = palette.ink,
        fontSize = 17.sp,
        fontWeight = FontWeight.SemiBold,
        modifier = Modifier.padding(horizontal = 16.dp).padding(top = topPadding + 10.dp, bottom = 8.dp),
    )
}

@Composable
private fun AlbumListRow(album: AlbumSummary, onClick: () -> Unit) {
    val palette = LocalSonarPalette.current
    val interaction = remember { MutableInteractionSource() }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 72.dp)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick)
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        RemoteArtwork(url = album.imageUrl, size = 58.dp, cornerRadius = 6.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
            Text(
                album.name,
                color = palette.ink,
                fontSize = 16.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                listOfNotNull(album.releaseDate, album.trackCount?.takeIf { it > 0 }?.let { "$it 首" })
                    .joinToString(" · "),
                color = palette.secondaryInk,
                fontSize = 12.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Icon(Icons.Rounded.ChevronRight, contentDescription = null, tint = palette.tertiaryInk, modifier = Modifier.size(16.dp))
    }
}

@Composable
private fun LoadingRow(title: String) {
    val palette = LocalSonarPalette.current
    Row(
        modifier = Modifier.fillMaxWidth().heightIn(min = 120.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        CircularProgressIndicator(color = palette.accent, modifier = Modifier.size(22.dp), strokeWidth = 2.dp)
        Spacer(Modifier.size(10.dp))
        Text(title, color = palette.secondaryInk, fontSize = 14.sp)
    }
}

@Composable
private fun SelectionBar(
    allSelected: Boolean,
    count: Int,
    canRemove: Boolean,
    onToggleAll: () -> Unit,
    onEnqueue: () -> Unit,
    onRemove: (() -> Unit)?,
) {
    val palette = LocalSonarPalette.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(44.dp)
            .background(palette.card)
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            text = if (allSelected) "取消全选" else "全选",
            color = palette.ink,
            fontSize = 14.sp,
            modifier = Modifier.clickable(onClick = onToggleAll),
        )
        Text("已选 $count", color = palette.secondaryInk, fontSize = 14.sp)
        Spacer(Modifier.weight(1f))
        Text(
            text = "入队",
            color = if (count > 0) palette.ink else palette.tertiaryInk,
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
            modifier = Modifier.clickable(enabled = count > 0, onClick = onEnqueue).padding(8.dp),
        )
        if (canRemove && onRemove != null) {
            Text(
                text = "移出",
                color = if (count > 0) palette.accent else palette.tertiaryInk,
                fontSize = 14.sp,
                fontWeight = FontWeight.Medium,
                modifier = Modifier.clickable(enabled = count > 0, onClick = onRemove).padding(8.dp),
            )
        }
    }
}

@Composable
private fun EmptyDetail(title: String, subtitle: String) {
    val palette = LocalSonarPalette.current
    Column(
        modifier = Modifier.fillMaxWidth().padding(vertical = 56.dp, horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(title, color = palette.ink, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
        Text(subtitle, color = palette.secondaryInk, fontSize = 13.sp, textAlign = TextAlign.Center)
    }
}

private fun dedupe(tracks: List<Track>): List<Track> = tracks.distinctBy { it.musicId }

private fun formatDuration(totalMs: Long): String {
    val totalSeconds = totalMs / 1000
    val hours = totalSeconds / 3600
    val minutes = (totalSeconds % 3600) / 60
    return if (hours > 0) "约 $hours 小时 $minutes 分钟" else "约 $minutes 分钟"
}
