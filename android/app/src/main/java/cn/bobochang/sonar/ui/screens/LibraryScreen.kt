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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.DeleteOutline
import androidx.compose.material.icons.rounded.Edit
import androidx.compose.material.icons.rounded.FavoriteBorder
import androidx.compose.material.icons.rounded.FileDownload
import androidx.compose.material.icons.rounded.FileUpload
import androidx.compose.material.icons.rounded.FolderOpen
import androidx.compose.material.icons.rounded.LibraryMusic
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Shuffle
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
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
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import cn.bobochang.sonar.data.library.BackupTarget
import cn.bobochang.sonar.data.library.PlaylistBackupCodec
import cn.bobochang.sonar.data.library.UserPlaylist
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.di.AppContainer
import cn.bobochang.sonar.ui.components.Artwork
import cn.bobochang.sonar.ui.components.EmptyState
import cn.bobochang.sonar.ui.components.SongRow
import cn.bobochang.sonar.ui.theme.LocalSonarPalette
import cn.bobochang.sonar.ui.viewmodel.LibraryViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream

private enum class LibraryTab(val label: String) {
    FAVORITES("收藏"),
    PLAYLISTS("歌单"),
    LOCAL("本地"),
    RECENT("最近"),
}

@Composable
fun LibraryScreen(
    container: AppContainer,
    snackbarHostState: SnackbarHostState,
    onOpenPlayer: () -> Unit,
    onOpenFavorites: () -> Unit,
    onOpenPlaylist: (String) -> Unit,
    onOpenLocal: () -> Unit,
) {
    val vm: LibraryViewModel = viewModel(
        factory = viewModelFactory { initializer { LibraryViewModel(container) } },
    )
    val favorites by vm.favorites.collectAsStateWithLifecycle()
    val playlists by vm.playlists.collectAsStateWithLifecycle()
    val recent by vm.recent.collectAsStateWithLifecycle()
    val localTracks by vm.localTracks.collectAsStateWithLifecycle()
    val palette = LocalSonarPalette.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var tab by remember { mutableStateOf(LibraryTab.FAVORITES) }
    var showCreate by remember { mutableStateOf(false) }
    var pendingImport by remember { mutableStateOf<ByteArray?>(null) }
    var renameTarget by remember { mutableStateOf<UserPlaylist?>(null) }
    var deleteTarget by remember { mutableStateOf<UserPlaylist?>(null) }

    val filePicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        if (uris.isNotEmpty()) vm.importLocalUris(uris)
    }
    val folderPicker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) vm.importLocalTree(uri)
    }
    val exportLauncher = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        if (uri != null) {
            scope.launch {
                val json = vm.exportFavorites() ?: return@launch
                withContext(Dispatchers.IO) {
                    context.contentResolver.openOutputStream(uri)?.use { output ->
                        output.write(json.toByteArray(Charsets.UTF_8))
                    }
                }
                snackbarHostState.showSnackbar("已导出收藏备份")
            }
        }
    }
    val importLauncher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            scope.launch {
                val bytes = withContext(Dispatchers.IO) {
                    runCatching {
                        context.contentResolver.openInputStream(uri)?.use { input ->
                            val output = ByteArrayOutputStream()
                            val buffer = ByteArray(8 * 1024)
                            while (true) {
                                val read = input.read(buffer)
                                if (read < 0) break
                                output.write(buffer, 0, read)
                                if (output.size() > PlaylistBackupCodec.MAX_BYTES) {
                                    throw IllegalArgumentException("备份文件超过 10 MB")
                                }
                            }
                            output.toByteArray()
                        }
                    }.getOrNull()
                }
                if (bytes == null) {
                    snackbarHostState.showSnackbar("无法读取备份文件")
                } else {
                    pendingImport = bytes
                }
            }
        }
    }

    LaunchedEffect(Unit) {
        vm.messages.collect { message -> snackbarHostState.showSnackbar(message) }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.background),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text("资料库", style = MaterialTheme.typography.headlineLarge, color = palette.ink)
                Text(
                    "留住喜欢的声音",
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.secondaryInk,
                )
            }
            IconButton(onClick = { importLauncher.launch(arrayOf("application/json")) }) {
                Icon(Icons.Rounded.FileUpload, contentDescription = "导入备份", tint = palette.ink)
            }
            IconButton(onClick = { exportLauncher.launch("Sonar-收藏备份.json") }) {
                Icon(Icons.Rounded.FileDownload, contentDescription = "导出收藏", tint = palette.ink)
            }
        }

        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            LibraryTab.entries.forEach { item ->
                FilterChip(
                    selected = tab == item,
                    onClick = { tab = item },
                    label = { Text(item.label) },
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = palette.accent.copy(alpha = 0.16f),
                        selectedLabelColor = palette.accent,
                        labelColor = palette.secondaryInk,
                    ),
                )
            }
        }

        Box(modifier = Modifier.weight(1f)) {
            when (tab) {
                LibraryTab.FAVORITES -> FavoritesPane(
                    tracks = favorites,
                    onPlay = { index -> vm.play(favorites, index); onOpenPlayer() },
                    onShuffle = { vm.play(favorites, 0, shuffle = true); onOpenPlayer() },
                    onFavorite = vm::toggleFavorite,
                    onPlayNext = vm::playNext,
                    onEnqueue = vm::enqueue,
                    onOpenFavorites = onOpenFavorites,
                )

                LibraryTab.PLAYLISTS -> PlaylistsPane(
                    playlists = playlists,
                    onCreate = { showCreate = true },
                    onOpen = onOpenPlaylist,
                    onRename = { renameTarget = it },
                    onDelete = { deleteTarget = it },
                )

                LibraryTab.LOCAL -> LocalPane(
                    tracks = localTracks,
                    onPlay = { index -> vm.play(localTracks, index); onOpenPlayer() },
                    onFavorite = vm::toggleFavorite,
                    onPlayNext = vm::playNext,
                    onEnqueue = vm::enqueue,
                    onPickFiles = {
                        filePicker.launch(arrayOf("audio/*"))
                    },
                    onPickFolder = { folderPicker.launch(null) },
                )

                LibraryTab.RECENT -> RecentPane(
                    tracks = recent,
                    favoriteIds = favorites.mapTo(mutableSetOf()) { it.musicId },
                    onPlay = { index -> vm.play(recent, index); onOpenPlayer() },
                    onFavorite = vm::toggleFavorite,
                    onPlayNext = vm::playNext,
                    onEnqueue = vm::enqueue,
                )
            }
        }
    }

    if (showCreate) {
        NameDialog(
            title = "新建歌单",
            confirmLabel = "创建",
            initial = "",
            onDismiss = { showCreate = false },
            onConfirm = { name ->
                showCreate = false
                vm.createPlaylist(name)
            },
        )
    }
    renameTarget?.let { target ->
        NameDialog(
            title = "重命名歌单",
            confirmLabel = "保存",
            initial = target.name,
            onDismiss = { renameTarget = null },
            onConfirm = { name ->
                vm.renamePlaylist(target.id, name)
                renameTarget = null
            },
        )
    }
    deleteTarget?.let { target ->
        AlertDialog(
            onDismissRequest = { deleteTarget = null },
            title = { Text("删除歌单") },
            text = { Text("确定删除「${target.name}」？歌曲仍会保留在资料库与收藏中。") },
            confirmButton = {
                TextButton(onClick = {
                    vm.deletePlaylist(target.id)
                    deleteTarget = null
                }) { Text("删除") }
            },
            dismissButton = {
                TextButton(onClick = { deleteTarget = null }) { Text("取消") }
            },
        )
    }
    pendingImport?.let { bytes ->
        AlertDialog(
            onDismissRequest = { pendingImport = null },
            title = { Text("导入歌单备份") },
            text = { Text("备份将按歌曲去重后合并。可以选择导入到收藏，或创建一个新歌单。") },
            confirmButton = {
                TextButton(onClick = {
                    vm.importBackup(bytes, BackupTarget.Favorites)
                    pendingImport = null
                }) { Text("导入到收藏") }
            },
            dismissButton = {
                TextButton(onClick = {
                    vm.importBackup(bytes, BackupTarget.NewPlaylist)
                    pendingImport = null
                }) { Text("新建歌单") }
            },
        )
    }
}

@Composable
private fun FavoritesPane(
    tracks: List<Track>,
    onPlay: (Int) -> Unit,
    onShuffle: () -> Unit,
    onFavorite: (Track) -> Unit,
    onPlayNext: (Track) -> Unit,
    onEnqueue: (Track) -> Unit,
    onOpenFavorites: () -> Unit,
) {
    val palette = LocalSonarPalette.current
    LazyColumn(contentPadding = PaddingValues(bottom = 24.dp)) {
        item {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "${tracks.size} 首歌曲",
                    style = MaterialTheme.typography.bodyMedium,
                    color = palette.secondaryInk,
                    modifier = Modifier.weight(1f),
                )
                FilledTonalButton(onClick = { onPlay(0) }, enabled = tracks.isNotEmpty()) {
                    Icon(Icons.Rounded.PlayArrow, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("播放全部")
                }
                IconButton(onClick = onShuffle, enabled = tracks.isNotEmpty()) {
                    Icon(Icons.Rounded.Shuffle, contentDescription = "随机播放", tint = palette.accent)
                }
            }
        }
        if (tracks.isEmpty()) {
            item {
                EmptyState(
                    icon = Icons.Rounded.FavoriteBorder,
                    title = "收藏还是空的",
                    subtitle = "在搜索结果或播放页点亮爱心，歌曲会出现在这里。",
                )
            }
        }
        itemsIndexed(tracks, key = { _, track -> track.musicId }) { index, track ->
            SongRow(
                track = track,
                isFavorite = true,
                onClick = { onPlay(index) },
                onFavorite = { onFavorite(track) },
                onPlayNext = { onPlayNext(track) },
                onEnqueue = { onEnqueue(track) },
            )
        }
        if (tracks.isNotEmpty()) {
            item {
                TextButton(
                    onClick = onOpenFavorites,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                ) { Text("打开收藏歌单") }
            }
        }
    }
}

@Composable
private fun PlaylistsPane(
    playlists: List<UserPlaylist>,
    onCreate: () -> Unit,
    onOpen: (String) -> Unit,
    onRename: (UserPlaylist) -> Unit,
    onDelete: (UserPlaylist) -> Unit,
) {
    val palette = LocalSonarPalette.current
    LazyColumn(contentPadding = PaddingValues(bottom = 24.dp)) {
        item {
            Surface(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 10.dp)
                    .clickable(onClick = onCreate),
                shape = RoundedCornerShape(14.dp),
                color = palette.card,
            ) {
                Row(
                    modifier = Modifier.padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Icon(Icons.Rounded.Add, contentDescription = null, tint = palette.accent)
                    Text("新建歌单", style = MaterialTheme.typography.titleMedium, color = palette.ink)
                }
            }
        }
        if (playlists.isEmpty()) {
            item {
                EmptyState(
                    icon = Icons.Rounded.LibraryMusic,
                    title = "还没有个人歌单",
                    subtitle = "新建歌单后，可以从搜索结果或收藏中添加歌曲。",
                )
            }
        }
        items(playlists, key = { it.id }) { playlist ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onOpen(playlist.id) }
                    .padding(horizontal = 16.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Box(
                    modifier = Modifier
                        .size(52.dp)
                        .background(palette.card, RoundedCornerShape(10.dp)),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(Icons.Rounded.LibraryMusic, contentDescription = null, tint = palette.accent)
                }
                Spacer(Modifier.width(12.dp))
                Text(
                    text = playlist.name,
                    style = MaterialTheme.typography.titleMedium,
                    color = palette.ink,
                    modifier = Modifier.weight(1f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                var menuOpen by remember { mutableStateOf(false) }
                Box {
                    IconButton(onClick = { menuOpen = true }) {
                        Icon(Icons.Rounded.MoreVert, contentDescription = "更多", tint = palette.secondaryInk)
                    }
                    DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                        DropdownMenuItem(
                            text = { Text("重命名") },
                            leadingIcon = { Icon(Icons.Rounded.Edit, contentDescription = null) },
                            onClick = { menuOpen = false; onRename(playlist) },
                        )
                        DropdownMenuItem(
                            text = { Text("删除") },
                            leadingIcon = { Icon(Icons.Rounded.DeleteOutline, contentDescription = null) },
                            onClick = { menuOpen = false; onDelete(playlist) },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun LocalPane(
    tracks: List<Track>,
    onPlay: (Int) -> Unit,
    onFavorite: (Track) -> Unit,
    onPlayNext: (Track) -> Unit,
    onEnqueue: (Track) -> Unit,
    onPickFiles: () -> Unit,
    onPickFolder: () -> Unit,
) {
    val palette = LocalSonarPalette.current
    LazyColumn(contentPadding = PaddingValues(bottom = 24.dp)) {
        item {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                FilledTonalButton(onClick = onPickFiles, modifier = Modifier.weight(1f)) {
                    Icon(Icons.Rounded.FileUpload, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("选择文件")
                }
                FilledTonalButton(onClick = onPickFolder, modifier = Modifier.weight(1f)) {
                    Icon(Icons.Rounded.FolderOpen, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(4.dp))
                    Text("导入文件夹")
                }
            }
        }
        if (tracks.isEmpty()) {
            item {
                EmptyState(
                    icon = Icons.Rounded.FolderOpen,
                    title = "还没有本地音乐",
                    subtitle = "支持 MP3、FLAC、M4A、WAV 等格式；文件夹导入会自动匹配同名 .lrc。",
                )
            }
        }
        itemsIndexed(tracks, key = { _, track -> track.musicId }) { index, track ->
            SongRow(
                track = track,
                isFavorite = true,
                onClick = { onPlay(index) },
                onFavorite = { onFavorite(track) },
                onPlayNext = { onPlayNext(track) },
                onEnqueue = { onEnqueue(track) },
            )
        }
    }
}

@Composable
private fun RecentPane(
    tracks: List<Track>,
    favoriteIds: Set<String>,
    onPlay: (Int) -> Unit,
    onFavorite: (Track) -> Unit,
    onPlayNext: (Track) -> Unit,
    onEnqueue: (Track) -> Unit,
) {
    LazyColumn(contentPadding = PaddingValues(bottom = 24.dp)) {
        if (tracks.isEmpty()) {
            item {
                EmptyState(
                    icon = Icons.Rounded.LibraryMusic,
                    title = "还没有播放记录",
                    subtitle = "播放过的歌曲会按最近顺序显示在这里。",
                )
            }
        }
        itemsIndexed(tracks, key = { _, track -> "recent_${track.musicId}" }) { index, track ->
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
}

@Composable
private fun NameDialog(
    title: String,
    confirmLabel: String,
    initial: String,
    onDismiss: () -> Unit,
    onConfirm: (String) -> Unit,
) {
    var value by remember(initial) { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            OutlinedTextField(
                value = value,
                onValueChange = { value = it.take(200) },
                singleLine = true,
                label = { Text("歌单名称") },
            )
        },
        confirmButton = {
            TextButton(onClick = { onConfirm(value.trim()) }, enabled = value.isNotBlank()) {
                Text(confirmLabel)
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("取消") } },
    )
}
