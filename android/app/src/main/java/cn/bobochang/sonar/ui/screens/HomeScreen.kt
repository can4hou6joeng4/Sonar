package cn.bobochang.sonar.ui.screens

import android.net.Uri
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
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.FolderOpen
import androidx.compose.material.icons.rounded.LibraryMusic
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.Shuffle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.FilledIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import cn.bobochang.sonar.data.library.UserPlaylist
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.di.AppContainer
import cn.bobochang.sonar.playback.PlayerUiState
import cn.bobochang.sonar.ui.components.Artwork
import cn.bobochang.sonar.ui.components.EmptyState
import cn.bobochang.sonar.ui.components.SectionHeader
import cn.bobochang.sonar.ui.components.SongRow
import cn.bobochang.sonar.ui.theme.LocalSonarPalette
import cn.bobochang.sonar.ui.viewmodel.HomeViewModel
import coil.compose.AsyncImage
import coil.request.ImageRequest

@Composable
fun HomeScreen(
    container: AppContainer,
    snackbarHostState: SnackbarHostState,
    onOpenSearch: () -> Unit,
    onOpenLibrary: () -> Unit,
    onOpenSettings: () -> Unit,
    onOpenPlayer: () -> Unit,
    onOpenFavorites: () -> Unit,
    onOpenPlaylist: (String) -> Unit,
) {
    val vm: HomeViewModel = viewModel(
        factory = viewModelFactory { initializer { HomeViewModel(container) } },
    )
    val favorites by vm.favorites.collectAsStateWithLifecycle()
    val recent by vm.recent.collectAsStateWithLifecycle()
    val playlists by vm.playlists.collectAsStateWithLifecycle()
    val playerState by vm.playerState.collectAsStateWithLifecycle()
    val palette = LocalSonarPalette.current
    var showImportChooser by remember { mutableStateOf(false) }

    val filePicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        if (uris.isNotEmpty()) vm.importLocalUris(uris)
    }
    val folderPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) vm.importLocalTree(uri)
    }

    LaunchedEffect(Unit) {
        vm.messages.collect { message -> snackbarHostState.showSnackbar(message) }
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.background),
        contentPadding = PaddingValues(bottom = 20.dp),
    ) {
        item {
            HomeTopBar(
                onOpenSettings = onOpenSettings,
                onOpenSearch = onOpenSearch,
            )
        }
        item {
            HeroCard(
                track = playerState.track,
                playerState = playerState,
                favorites = favorites,
                onPlayCurrent = onOpenPlayer,
                onToggle = { container.playerConnection.toggle() },
                onPlayFavorites = { vm.play(favorites, 0, shuffle = false) },
                onShuffleFavorites = { vm.play(favorites, 0, shuffle = true) },
                onOpenSearch = onOpenSearch,
            )
        }
        item {
            QuickActions(
                onSearch = onOpenSearch,
                onLibrary = onOpenLibrary,
                onImport = { showImportChooser = true },
                onSettings = onOpenSettings,
            )
        }
        if (favorites.isNotEmpty()) {
            item {
                SectionHeader(
                    title = "我的收藏",
                    action = "查看全部",
                    onAction = onOpenFavorites,
                )
            }
            itemsIndexed(favorites.take(6), key = { _, track -> track.musicId }) { index, track ->
                SongRow(
                    track = track,
                    isFavorite = true,
                    onClick = { vm.play(favorites, index) ; onOpenPlayer() },
                    onFavorite = { vm.toggleFavorite(track) },
                    onPlayNext = { vm.playNext(track) },
                    onEnqueue = { vm.enqueue(track) },
                )
            }
        }
        if (playlists.isNotEmpty()) {
            item {
                SectionHeader(
                    title = "我的歌单",
                    action = "管理",
                    onAction = onOpenLibrary,
                )
            }
            item {
                LazyRow(
                    contentPadding = PaddingValues(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    items(playlists.take(10), key = { it.id }) { playlist ->
                        PlaylistCard(playlist = playlist, onClick = { onOpenPlaylist(playlist.id) })
                    }
                }
            }
        }
        if (recent.isNotEmpty()) {
            item {
                SectionHeader(title = "最近播放", action = "资料库", onAction = onOpenLibrary)
            }
            itemsIndexed(recent.take(5), key = { _, track -> "recent_${track.musicId}" }) { index, track ->
                SongRow(
                    track = track,
                    isFavorite = favorites.any { it.musicId == track.musicId },
                    onClick = { vm.play(recent, index); onOpenPlayer() },
                    onFavorite = { vm.toggleFavorite(track) },
                    onPlayNext = { vm.playNext(track) },
                    onEnqueue = { vm.enqueue(track) },
                )
            }
        }
        if (favorites.isEmpty() && recent.isEmpty()) {
            item {
                EmptyState(
                    icon = Icons.Rounded.LibraryMusic,
                    title = "还没有收藏歌曲",
                    subtitle = "搜索并收藏喜欢的音乐，或从本地导入音频。",
                    actionLabel = "开始搜索",
                    onAction = onOpenSearch,
                )
            }
        }
    }

    if (showImportChooser) {
        AlertDialog(
            onDismissRequest = { showImportChooser = false },
            title = { Text("导入本地音乐") },
            text = { Text("选择单个/多个音频文件，或导入整个文件夹并自动匹配同名 .lrc 歌词。") },
            confirmButton = {
                TextButton(onClick = {
                    showImportChooser = false
                    filePicker.launch(arrayOf("audio/*"))
                }) { Text("选择文件") }
            },
            dismissButton = {
                TextButton(onClick = {
                    showImportChooser = false
                    folderPicker.launch(null)
                }) { Text("选择文件夹") }
            },
        )
    }
}

@Composable
private fun HomeTopBar(onOpenSettings: () -> Unit, onOpenSearch: () -> Unit) {
    val palette = LocalSonarPalette.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = "Sonar",
                style = MaterialTheme.typography.headlineLarge,
                color = palette.ink,
            )
            Text(
                text = "在深水里靠声音辨路",
                style = MaterialTheme.typography.bodySmall,
                color = palette.secondaryInk,
            )
        }
        IconButton(onClick = onOpenSearch) {
            Icon(Icons.Rounded.Search, contentDescription = "搜索", tint = palette.ink)
        }
        IconButton(onClick = onOpenSettings) {
            Icon(Icons.Rounded.Settings, contentDescription = "设置", tint = palette.ink)
        }
    }
}

@Composable
private fun HeroCard(
    track: Track?,
    playerState: PlayerUiState,
    favorites: List<Track>,
    onPlayCurrent: () -> Unit,
    onToggle: () -> Unit,
    onPlayFavorites: () -> Unit,
    onShuffleFavorites: () -> Unit,
    onOpenSearch: () -> Unit,
) {
    val palette = LocalSonarPalette.current
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .height(250.dp)
            .padding(horizontal = 16.dp),
        shape = RoundedCornerShape(24.dp),
        color = palette.card,
    ) {
        Box(modifier = Modifier.fillMaxSize().clickable(onClick = onPlayCurrent)) {
            if (track?.coverUrl != null) {
                AsyncImage(
                    model = ImageRequest.Builder(LocalContext.current).data(track.coverUrl).crossfade(true).build(),
                    contentDescription = null,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxSize(),
                )
            } else {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(
                            Brush.linearGradient(
                                listOf(Color(0xFF4A1A1C), Color(0xFF16161B)),
                            ),
                        ),
                )
            }
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .background(
                        Brush.verticalGradient(
                            listOf(Color.Transparent, palette.background.copy(alpha = 0.35f), palette.background.copy(alpha = 0.95f)),
                        ),
                    ),
            )
            Column(
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .fillMaxWidth()
                    .padding(20.dp),
            ) {
                Text(
                    text = if (track != null) "继续聆听" else "开始你的聆听",
                    style = MaterialTheme.typography.labelMedium,
                    color = Color.White.copy(alpha = 0.8f),
                )
                Text(
                    text = track?.title ?: "搜索一首歌，或导入本地音乐",
                    style = MaterialTheme.typography.headlineMedium,
                    color = Color.White,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = track?.artist ?: "Sonar",
                    style = MaterialTheme.typography.bodyMedium,
                    color = Color.White.copy(alpha = 0.7f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Spacer(Modifier.height(14.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (track != null) {
                        FilledIconButton(onClick = onToggle, modifier = Modifier.size(48.dp)) {
                            Icon(
                                imageVector = if (playerState.isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                                contentDescription = if (playerState.isPlaying) "暂停" else "播放",
                                tint = palette.accent,
                            )
                        }
                        OutlinedButton(onClick = onPlayFavorites, enabled = favorites.isNotEmpty()) {
                            Text("播放收藏")
                        }
                        IconButton(onClick = onShuffleFavorites, enabled = favorites.isNotEmpty()) {
                            Icon(Icons.Rounded.Shuffle, contentDescription = "随机播放", tint = Color.White)
                        }
                    } else {
                        Button(onClick = onOpenSearch) { Text("去搜索") }
                    }
                }
            }
        }
    }
}

@Composable
private fun QuickActions(
    onSearch: () -> Unit,
    onLibrary: () -> Unit,
    onImport: () -> Unit,
    onSettings: () -> Unit,
) {
    val palette = LocalSonarPalette.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        QuickAction("搜索", Icons.Rounded.Search, onSearch, Modifier.weight(1f))
        QuickAction("资料库", Icons.Rounded.LibraryMusic, onLibrary, Modifier.weight(1f))
        QuickAction("导入", Icons.Rounded.FolderOpen, onImport, Modifier.weight(1f))
        QuickAction("设置", Icons.Rounded.Settings, onSettings, Modifier.weight(1f))
    }
}

@Composable
private fun QuickAction(
    label: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalSonarPalette.current
    Surface(
        modifier = modifier
            .heightIn(min = 48.dp)
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(14.dp),
        color = palette.card,
    ) {
        Column(
            modifier = Modifier.padding(vertical = 12.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Icon(icon, contentDescription = null, tint = palette.accent, modifier = Modifier.size(22.dp))
            Text(label, style = MaterialTheme.typography.labelMedium, color = palette.secondaryInk)
        }
    }
}

@Composable
private fun PlaylistCard(playlist: UserPlaylist, onClick: () -> Unit) {
    val palette = LocalSonarPalette.current
    Surface(
        modifier = Modifier
            .width(112.dp)
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(14.dp),
        color = palette.card,
    ) {
        Column(modifier = Modifier.padding(8.dp)) {
            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(96.dp)
                    .clip(RoundedCornerShape(10.dp))
                    .background(
                        Brush.linearGradient(
                            listOf(palette.accent.copy(alpha = 0.5f), palette.elevated),
                        ),
                    ),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Rounded.LibraryMusic,
                    contentDescription = null,
                    tint = Color.White.copy(alpha = 0.9f),
                    modifier = Modifier.size(30.dp),
                )
            }
            Spacer(Modifier.height(7.dp))
            Text(
                text = playlist.name,
                style = MaterialTheme.typography.labelMedium,
                color = palette.ink,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}
