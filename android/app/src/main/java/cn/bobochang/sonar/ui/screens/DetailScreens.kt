package cn.bobochang.sonar.ui.screens

import android.content.Context
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.rounded.ArrowBack
import androidx.compose.material.icons.rounded.CloudOff
import androidx.compose.material.icons.rounded.DeleteOutline
import androidx.compose.material.icons.rounded.FileDownload
import androidx.compose.material.icons.rounded.LibraryMusic
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Shuffle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import cn.bobochang.sonar.data.library.BackupTarget
import cn.bobochang.sonar.data.model.AlbumSummary
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.di.AppContainer
import cn.bobochang.sonar.ui.components.Artwork
import cn.bobochang.sonar.ui.components.EmptyState
import cn.bobochang.sonar.ui.components.SectionHeader
import cn.bobochang.sonar.ui.components.SongRow
import cn.bobochang.sonar.ui.theme.LocalSonarPalette
import cn.bobochang.sonar.ui.viewmodel.LibraryViewModel
import cn.bobochang.sonar.ui.viewmodel.RemoteViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun PlaylistDetailScreen(
    container: AppContainer,
    playlistId: String?,
    onBack: () -> Unit,
    onOpenPlayer: () -> Unit,
    snackbarHostState: SnackbarHostState,
) {
    val vm: LibraryViewModel = viewModel(
        factory = viewModelFactory { initializer { LibraryViewModel(container) } },
    )
    val favorites by vm.favorites.collectAsStateWithLifecycle()
    val playlists by vm.playlists.collectAsStateWithLifecycle()
    val playlistTracks by remember(playlistId) {
        container.library.observePlaylistTracks(playlistId.orEmpty())
    }.collectAsStateWithLifecycle(initialValue = emptyList())

    val isFavorites = playlistId == null
    val tracks = if (isFavorites) favorites else playlistTracks
    val favoriteIds = favorites.mapTo(mutableSetOf()) { it.musicId }
    val title = if (isFavorites) {
        "我的收藏"
    } else {
        playlists.firstOrNull { it.id == playlistId }?.name ?: "歌单"
    }
    val subtitle = if (isFavorites) {
        "共 ${tracks.size} 首收藏"
    } else {
        "共 ${tracks.size} 首 · 可在此移除"
    }
    val palette = LocalSonarPalette.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var menuOpen by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    val exportLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/json"),
    ) { uri ->
        val id = playlistId
        if (uri != null && id != null) {
            scope.launch {
                val json = vm.exportPlaylist(id)
                if (json == null) {
                    snackbarHostState.showSnackbar("导出歌单失败")
                    return@launch
                }
                withContext(Dispatchers.IO) {
                    context.contentResolver.openOutputStream(uri)?.use { output ->
                        output.write(json.toByteArray(Charsets.UTF_8))
                    }
                }
                snackbarHostState.showSnackbar("已导出歌单备份")
            }
        }
    }

    LaunchedEffect(Unit) {
        vm.messages.collect { message -> snackbarHostState.showSnackbar(message) }
    }

    DetailScaffold(
        title = title,
        subtitle = subtitle,
        imageUrl = tracks.firstOrNull()?.coverUrl,
        onBack = onBack,
        onPlayAll = if (tracks.isEmpty()) null else {
            {
                vm.play(tracks, 0)
                onOpenPlayer()
            }
        },
        onShuffle = if (tracks.isEmpty()) null else {
            {
                vm.play(tracks, 0, shuffle = true)
                onOpenPlayer()
            }
        },
        isEmpty = tracks.isEmpty(),
        emptyTitle = if (isFavorites) "还没有收藏歌曲" else "歌单还是空的",
        emptySubtitle = if (isFavorites) {
            "在歌曲菜单中选择收藏，喜欢的音乐就会出现在这里。"
        } else {
            "可以从搜索结果或远程歌单中把歌曲加入这个歌单。"
        },
        headerAction = if (isFavorites) {
            null
        } else {
            {
                Box {
                    IconButton(onClick = { menuOpen = true }) {
                        Icon(
                            Icons.Rounded.MoreVert,
                            contentDescription = "歌单操作",
                            tint = palette.ink,
                        )
                    }
                    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                        DropdownMenuItem(
                            text = { Text("导出歌单备份") },
                            leadingIcon = { Icon(Icons.Rounded.FileDownload, contentDescription = null) },
                            onClick = {
                                menuOpen = false
                                val safeName = title
                                    .replace(Regex("""[\\/:*?"<>|]"""), "_")
                                    .take(80)
                                    .ifBlank { "Sonar歌单" }
                                exportLauncher.launch("$safeName-备份.json")
                            },
                        )
                        DropdownMenuItem(
                            text = { Text("删除歌单") },
                            leadingIcon = { Icon(Icons.Rounded.DeleteOutline, contentDescription = null) },
                            onClick = {
                                menuOpen = false
                                confirmDelete = true
                            },
                        )
                    }
                }
            }
        },
    ) {
        item { SectionHeader(title = "歌曲") }
        itemsIndexed(tracks, key = { index, track -> "$index-${track.musicId}" }) { index, track ->
            SongRow(
                track = track,
                isFavorite = track.musicId in favoriteIds,
                onClick = {
                    vm.play(tracks, index)
                    onOpenPlayer()
                },
                onFavorite = { vm.toggleFavorite(track) },
                onPlayNext = { vm.playNext(track) },
                onEnqueue = { vm.enqueue(track) },
                onRemove = if (isFavorites) {
                    null
                } else {
                    { vm.removeFromPlaylist(playlistId.orEmpty(), track) }
                },
            )
        }
    }

    val deleteId = playlistId
    if (confirmDelete && deleteId != null) {
        AlertDialog(
            onDismissRequest = { confirmDelete = false },
            title = { Text("删除歌单") },
            text = { Text("确定删除「$title」？歌曲仍会保留在收藏与资料库中。") },
            confirmButton = {
                TextButton(onClick = {
                    confirmDelete = false
                    vm.deletePlaylist(deleteId)
                    onBack()
                }) { Text("删除") }
            },
            dismissButton = {
                TextButton(onClick = { confirmDelete = false }) { Text("取消") }
            },
        )
    }
}

@Composable
fun RemotePlaylistScreen(
    container: AppContainer,
    playlistId: String,
    onBack: () -> Unit,
    onOpenPlayer: () -> Unit,
    snackbarHostState: SnackbarHostState,
) {
    val vm: RemoteViewModel = viewModel(
        factory = viewModelFactory { initializer { RemoteViewModel(container) } },
    )
    val state by vm.state.collectAsStateWithLifecycle()
    val favoriteIds by vm.favoriteIds.collectAsStateWithLifecycle()
    var menuOpen by remember { mutableStateOf(false) }
    val palette = LocalSonarPalette.current

    LaunchedEffect(playlistId) { vm.loadPlaylist(playlistId) }
    LaunchedEffect(Unit) {
        vm.messages.collect { message -> snackbarHostState.showSnackbar(message) }
    }

    DetailScaffold(
        title = state.title.ifBlank { "远程歌单" },
        subtitle = state.subtitle,
        imageUrl = state.imageUrl,
        loading = state.loading,
        error = state.error,
        onBack = onBack,
        onRetry = { vm.loadPlaylist(playlistId) },
        onPlayAll = if (state.tracks.isEmpty()) null else {
            {
                vm.play(0)
                onOpenPlayer()
            }
        },
        onShuffle = if (state.tracks.isEmpty()) null else {
            {
                vm.play(0, shuffle = true)
                onOpenPlayer()
            }
        },
        isEmpty = state.tracks.isEmpty(),
        emptyTitle = "歌单暂无歌曲",
        emptySubtitle = "该歌单可能没有公开曲目，或接口暂未返回数据。",
        headerAction = {
            Box {
                IconButton(onClick = { menuOpen = true }) {
                    Icon(Icons.Rounded.MoreVert, contentDescription = "更多", tint = palette.ink)
                }
                DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                    DropdownMenuItem(
                        text = { Text("收藏全部") },
                        onClick = {
                            menuOpen = false
                            vm.importPlaylist(BackupTarget.Favorites)
                        },
                    )
                    DropdownMenuItem(
                        text = { Text("导入为我自己的歌单") },
                        onClick = {
                            menuOpen = false
                            vm.importPlaylist(BackupTarget.NewPlaylist)
                        },
                    )
                }
            }
        },
    ) {
        item { SectionHeader(title = "歌曲") }
        trackItems(
            tracks = state.tracks,
            favoriteIds = favoriteIds,
            onPlay = { index ->
                vm.play(index)
                onOpenPlayer()
            },
            onFavorite = vm::toggleFavorite,
            onPlayNext = vm::playNext,
            onEnqueue = vm::enqueue,
        )
    }
}

@Composable
fun ArtistDetailScreen(
    container: AppContainer,
    artistId: String,
    onBack: () -> Unit,
    onOpenPlayer: () -> Unit,
    onOpenAlbum: (String) -> Unit,
    snackbarHostState: SnackbarHostState,
) {
    val vm: RemoteViewModel = viewModel(
        factory = viewModelFactory { initializer { RemoteViewModel(container) } },
    )
    val state by vm.state.collectAsStateWithLifecycle()
    val favoriteIds by vm.favoriteIds.collectAsStateWithLifecycle()

    LaunchedEffect(artistId) { vm.loadArtist(artistId) }
    LaunchedEffect(Unit) {
        vm.messages.collect { message -> snackbarHostState.showSnackbar(message) }
    }

    DetailScaffold(
        title = state.title.ifBlank { "歌手" },
        subtitle = state.subtitle,
        imageUrl = state.imageUrl,
        loading = state.loading,
        error = state.error,
        onBack = onBack,
        onRetry = { vm.loadArtist(artistId) },
        onPlayAll = if (state.tracks.isEmpty()) null else {
            {
                vm.play(0)
                onOpenPlayer()
            }
        },
        onShuffle = if (state.tracks.isEmpty()) null else {
            {
                vm.play(0, shuffle = true)
                onOpenPlayer()
            }
        },
        isEmpty = state.tracks.isEmpty() && state.albums.isEmpty(),
        emptyTitle = "没有找到歌手内容",
        emptySubtitle = "可能没有公开的热门歌曲或专辑。",
    ) {
        if (state.tracks.isNotEmpty()) {
            item { SectionHeader(title = "热门歌曲") }
            trackItems(
                tracks = state.tracks,
                favoriteIds = favoriteIds,
                onPlay = { index ->
                    vm.play(index)
                    onOpenPlayer()
                },
                onFavorite = vm::toggleFavorite,
                onPlayNext = vm::playNext,
                onEnqueue = vm::enqueue,
            )
        }
        if (state.albums.isNotEmpty()) {
            item { SectionHeader(title = "专辑") }
            item {
                LazyRow(
                    contentPadding = PaddingValues(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    items(state.albums, key = { it.stableId }) { album ->
                        AlbumCard(album = album, onClick = { onOpenAlbum(album.id) })
                    }
                }
            }
        }
    }
}

@Composable
fun AlbumDetailScreen(
    container: AppContainer,
    albumId: String,
    onBack: () -> Unit,
    onOpenPlayer: () -> Unit,
    snackbarHostState: SnackbarHostState,
) {
    val vm: RemoteViewModel = viewModel(
        factory = viewModelFactory { initializer { RemoteViewModel(container) } },
    )
    val state by vm.state.collectAsStateWithLifecycle()
    val favoriteIds by vm.favoriteIds.collectAsStateWithLifecycle()

    LaunchedEffect(albumId) { vm.loadAlbum(albumId) }
    LaunchedEffect(Unit) {
        vm.messages.collect { message -> snackbarHostState.showSnackbar(message) }
    }

    DetailScaffold(
        title = state.title.ifBlank { "专辑" },
        subtitle = state.subtitle,
        imageUrl = state.imageUrl,
        loading = state.loading,
        error = state.error,
        onBack = onBack,
        onRetry = { vm.loadAlbum(albumId) },
        onPlayAll = if (state.tracks.isEmpty()) null else {
            {
                vm.play(0)
                onOpenPlayer()
            }
        },
        onShuffle = if (state.tracks.isEmpty()) null else {
            {
                vm.play(0, shuffle = true)
                onOpenPlayer()
            }
        },
        isEmpty = state.tracks.isEmpty(),
        emptyTitle = "专辑暂无歌曲",
        emptySubtitle = "接口暂未返回可播放的曲目。",
    ) {
        item { SectionHeader(title = "歌曲") }
        trackItems(
            tracks = state.tracks,
            favoriteIds = favoriteIds,
            onPlay = { index ->
                vm.play(index)
                onOpenPlayer()
            },
            onFavorite = vm::toggleFavorite,
            onPlayNext = vm::playNext,
            onEnqueue = vm::enqueue,
        )
    }
}

@Composable
private fun DetailScaffold(
    title: String,
    subtitle: String,
    imageUrl: String?,
    onBack: () -> Unit,
    onRetry: (() -> Unit)? = null,
    onPlayAll: (() -> Unit)? = null,
    onShuffle: (() -> Unit)? = null,
    loading: Boolean = false,
    error: String? = null,
    isEmpty: Boolean = false,
    emptyTitle: String = "暂无内容",
    emptySubtitle: String = "这里还没有可显示的内容。",
    headerAction: (@Composable () -> Unit)? = null,
    content: LazyListScope.() -> Unit,
) {
    val palette = LocalSonarPalette.current
    BackHandler(onBack = onBack)

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.background),
        contentPadding = PaddingValues(bottom = 28.dp),
    ) {
        item {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 8.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(onClick = onBack) {
                    Icon(
                        imageVector = Icons.AutoMirrored.Rounded.ArrowBack,
                        contentDescription = "返回",
                        tint = palette.ink,
                    )
                }
                Text(
                    text = title,
                    style = MaterialTheme.typography.titleMedium,
                    color = palette.ink,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                headerAction?.invoke()
            }
        }
        item {
            Column(modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Artwork(url = imageUrl, size = 128.dp, corner = 18.dp)
                    Spacer(Modifier.width(16.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            text = title,
                            style = MaterialTheme.typography.headlineMedium,
                            color = palette.ink,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Spacer(Modifier.height(4.dp))
                        Text(
                            text = subtitle,
                            style = MaterialTheme.typography.bodySmall,
                            color = palette.secondaryInk,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
                Spacer(Modifier.height(16.dp))
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Button(
                        onClick = { onPlayAll?.invoke() },
                        enabled = onPlayAll != null,
                        modifier = Modifier.weight(1f),
                    ) {
                        Icon(Icons.Rounded.PlayArrow, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("播放全部")
                    }
                    OutlinedButton(
                        onClick = { onShuffle?.invoke() },
                        enabled = onShuffle != null,
                        modifier = Modifier.weight(1f),
                    ) {
                        Icon(Icons.Rounded.Shuffle, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(6.dp))
                        Text("随机播放")
                    }
                }
                Spacer(Modifier.height(8.dp))
            }
        }
        when {
            loading -> item {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(140.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    CircularProgressIndicator(color = palette.accent)
                }
            }

            error != null -> item {
                EmptyState(
                    icon = Icons.Rounded.CloudOff,
                    title = "加载失败",
                    subtitle = error,
                    actionLabel = if (onRetry != null) "重试" else null,
                    onAction = onRetry,
                )
            }

            isEmpty -> item {
                EmptyState(
                    icon = Icons.Rounded.LibraryMusic,
                    title = emptyTitle,
                    subtitle = emptySubtitle,
                )
            }

            else -> content()
        }
    }
}

private fun LazyListScope.trackItems(
    tracks: List<Track>,
    favoriteIds: Set<String>,
    onPlay: (Int) -> Unit,
    onFavorite: (Track) -> Unit,
    onPlayNext: (Track) -> Unit,
    onEnqueue: (Track) -> Unit,
) {
    itemsIndexed(tracks, key = { index, track -> "$index-${track.musicId}" }) { index, track ->
        SongRow(
            track = track,
            isFavorite = track.musicId in favoriteIds,
            onClick = { onPlay(index) },
            onFavorite = { onFavorite(track) },
            onPlayNext = { onPlayNext(track) },
            onEnqueue = { onEnqueue(track) },
        )
    }
}

@Composable
private fun AlbumCard(album: AlbumSummary, onClick: () -> Unit) {
    val palette = LocalSonarPalette.current
    Column(
        modifier = Modifier
            .width(124.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(palette.card)
            .clickable(onClick = onClick)
            .padding(8.dp),
    ) {
        Artwork(
            url = album.imageUrl,
            size = 108.dp,
            corner = 10.dp,
        )
        Spacer(Modifier.height(7.dp))
        Text(
            text = album.name,
            style = MaterialTheme.typography.labelMedium,
            color = palette.ink,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            text = album.releaseDate ?: album.artist,
            style = MaterialTheme.typography.labelSmall,
            color = palette.secondaryInk,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Spacer(Modifier.height(2.dp))
    }
}
