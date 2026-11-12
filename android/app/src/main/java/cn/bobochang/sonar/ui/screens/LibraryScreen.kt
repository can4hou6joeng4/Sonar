package cn.bobochang.sonar.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.LibraryMusic
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Shuffle
import androidx.compose.material.icons.rounded.UploadFile
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cn.bobochang.sonar.data.library.UserPlaylist
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.di.AppContainer
import cn.bobochang.sonar.playback.PlaybackMode
import cn.bobochang.sonar.playback.PlayerUiState
import cn.bobochang.sonar.ui.components.LocalToast
import cn.bobochang.sonar.ui.components.SongLeading
import cn.bobochang.sonar.ui.components.SongRow
import cn.bobochang.sonar.ui.components.SongTrailing
import cn.bobochang.sonar.ui.theme.bouncePress
import cn.bobochang.sonar.ui.theme.circleIconPress
import cn.bobochang.sonar.ui.theme.LocalSonarPalette
import kotlinx.coroutines.launch

private enum class LibraryScope(val label: String, val icon: androidx.compose.ui.graphics.vector.ImageVector) {
    FAVORITES("收藏", Icons.Rounded.LibraryMusic),
    PLAYLISTS("歌单", Icons.Rounded.MusicNote),
    LOCAL("本地", Icons.Rounded.Folder),
    RECENT("最近", Icons.Rounded.PlayArrow),
}

/** 资料库 Tab：沿用 iOS 视觉语言，同时保留 Android 的收藏 / 歌单 / 本地 / 最近四种入口。 */
@Composable
fun LibraryScreen(
    container: AppContainer,
    playerState: PlayerUiState,
    bottomPadding: Dp,
    onOpenSettings: () -> Unit,
    onOpenPlaylist: (String) -> Unit,
    onImportFiles: () -> Unit,
    onImportFolder: () -> Unit,
    onSongAction: (Track) -> Unit,
) {
    val palette = LocalSonarPalette.current
    val toast = LocalToast.current
    val scope = rememberCoroutineScope()
    var selectedScope by remember { mutableStateOf(LibraryScope.FAVORITES) }
    var showCreateDialog by remember { mutableStateOf(false) }
    var newName by remember { mutableStateOf("") }
    val favorites by container.library.observeFavorites().collectAsState(initial = emptyList())
    val playlists by container.library.observePlaylists().collectAsState(initial = emptyList())
    val localTracks by container.library.observeLocalTracks().collectAsState(initial = emptyList())
    val recent by container.library.observeRecent().collectAsState(initial = emptyList())
    val statusTop = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.background)
            .padding(top = statusTop),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 8.dp)
                .padding(top = 4.dp, bottom = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            LibrarySettingsButton(onOpenSettings = onOpenSettings)
            ScopePicker(
                selected = selectedScope,
                onSelect = { selectedScope = it },
                modifier = Modifier.weight(1f).padding(start = 4.dp),
            )
        }

        when (selectedScope) {
            LibraryScope.FAVORITES -> TrackList(
                tracks = favorites,
                playerState = playerState,
                bottomPadding = bottomPadding,
                emptyTitle = "这个歌单还没有歌曲",
                emptySubtitle = "在搜索结果或歌手页面选择“收藏到歌单”，歌曲会保存在这里",
                showHeader = true,
                onPlayAll = { shuffled ->
                    if (favorites.isNotEmpty()) {
                        scope.launch {
                            val quality = container.settings.snapshot().quality
                            container.playerConnection.setPlaybackMode(
                                if (shuffled) PlaybackMode.SHUFFLE else PlaybackMode.SEQUENCE,
                            )
                            container.playerConnection.playTracks(
                                if (shuffled) favorites.shuffled() else favorites,
                                0,
                                quality,
                            )
                        }
                    }
                },
                onPlay = { index ->
                    scope.launch {
                        val quality = container.settings.snapshot().quality
                        container.playerConnection.setPlaybackMode(PlaybackMode.SEQUENCE)
                        container.playerConnection.playTracks(favorites, index, quality)
                    }
                },
                onSongAction = onSongAction,
            )

            LibraryScope.PLAYLISTS -> LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(
                    start = 16.dp,
                    end = 16.dp,
                    bottom = bottomPadding + 20.dp,
                ),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                item(key = "create") {
                    PlaylistRow(
                        title = "新建歌单",
                        subtitle = "创建一个新的个人歌单",
                        icon = Icons.Rounded.Add,
                        onClick = { showCreateDialog = true },
                    )
                }
                items(playlists, key = { it.id }) { playlist ->
                    PlaylistRow(
                        title = playlist.name,
                        subtitle = if (playlist.system) "系统歌单" else "个人歌单",
                        icon = Icons.Rounded.LibraryMusic,
                        onClick = { onOpenPlaylist(playlist.id) },
                    )
                }
                if (playlists.isEmpty()) {
                    item(key = "empty") {
                        EmptyPane("还没有歌单", "新建一个歌单，把喜欢的歌分组收藏")
                    }
                }
            }

            LibraryScope.LOCAL -> Column(Modifier.fillMaxSize()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp, vertical = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    ImportButton("导入文件", Icons.Rounded.UploadFile, Modifier.weight(1f), onImportFiles)
                    ImportButton("导入文件夹", Icons.Rounded.Folder, Modifier.weight(1f), onImportFolder)
                }
                TrackList(
                    tracks = localTracks,
                    playerState = playerState,
                    bottomPadding = bottomPadding,
                    emptyTitle = "还没有本地歌曲",
                    emptySubtitle = "从设备中选择音频或整个文件夹导入",
                    showHeader = false,
                    onPlayAll = { shuffled ->
                        if (localTracks.isNotEmpty()) {
                            scope.launch {
                                val quality = container.settings.snapshot().quality
                                container.playerConnection.setPlaybackMode(
                                    if (shuffled) PlaybackMode.SHUFFLE else PlaybackMode.SEQUENCE,
                                )
                                container.playerConnection.playTracks(
                                    if (shuffled) localTracks.shuffled() else localTracks,
                                    0,
                                    quality,
                                )
                            }
                        }
                    },
                    onPlay = { index ->
                        scope.launch {
                            val quality = container.settings.snapshot().quality
                            container.playerConnection.playTracks(localTracks, index, quality)
                        }
                    },
                    onSongAction = onSongAction,
                )
            }

            LibraryScope.RECENT -> TrackList(
                tracks = recent,
                playerState = playerState,
                bottomPadding = bottomPadding,
                emptyTitle = "还没有播放记录",
                emptySubtitle = "播放过的歌曲会出现在这里",
                showHeader = false,
                onPlayAll = { shuffled ->
                    if (recent.isNotEmpty()) {
                        scope.launch {
                            val quality = container.settings.snapshot().quality
                            container.playerConnection.setPlaybackMode(
                                if (shuffled) PlaybackMode.SHUFFLE else PlaybackMode.SEQUENCE,
                            )
                            container.playerConnection.playTracks(
                                if (shuffled) recent.shuffled() else recent,
                                0,
                                quality,
                            )
                        }
                    }
                },
                onPlay = { index ->
                    scope.launch {
                        val quality = container.settings.snapshot().quality
                        container.playerConnection.playTracks(recent, index, quality)
                    }
                },
                onSongAction = onSongAction,
            )
        }
    }

    if (showCreateDialog) {
        AlertDialog(
            onDismissRequest = { showCreateDialog = false },
            title = { Text("新建歌单") },
            text = {
                OutlinedTextField(
                    value = newName,
                    onValueChange = { newName = it },
                    placeholder = { Text("歌单名称") },
                    singleLine = true,
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        val name = newName.trim()
                        if (name.isNotEmpty()) {
                            scope.launch {
                                container.library.createPlaylist(name)
                                toast.show("已创建歌单")
                            }
                        }
                        newName = ""
                        showCreateDialog = false
                    },
                ) { Text("创建") }
            },
            dismissButton = {
                TextButton(onClick = { showCreateDialog = false }) { Text("取消") }
            },
        )
    }
}

@Composable
private fun LibrarySettingsButton(onOpenSettings: () -> Unit) {
    val palette = LocalSonarPalette.current
    val interaction = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }
    Box(
        modifier = Modifier
            .size(44.dp)
            .then(circleIconPress(interaction, 38.dp))
            .clickable(interactionSource = interaction, indication = null, onClick = onOpenSettings),
        contentAlignment = Alignment.Center,
    ) {
        Icon(Icons.Rounded.Settings, contentDescription = "设置", tint = palette.ink, modifier = Modifier.size(20.dp))
    }
}

@Composable
private fun ScopePicker(
    selected: LibraryScope,
    onSelect: (LibraryScope) -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalSonarPalette.current
    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(palette.inputFill, CircleShape)
            .padding(3.dp),
    ) {
        LibraryScope.entries.forEach { scope ->
            val isSelected = scope == selected
            Box(
                modifier = Modifier
                    .weight(1f)
                    .heightIn44()
                    .clip(CircleShape)
                    .background(if (isSelected) palette.background else Color.Transparent)
                    .clickable { onSelect(scope) },
                contentAlignment = Alignment.Center,
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(5.dp),
                ) {
                    Icon(
                        scope.icon,
                        contentDescription = null,
                        tint = if (isSelected) palette.ink else palette.secondaryInk,
                        modifier = Modifier.size(14.dp),
                    )
                    Text(
                        text = scope.label,
                        color = if (isSelected) palette.ink else palette.secondaryInk,
                        fontSize = 14.sp,
                        fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
                    )
                }
            }
        }
    }
}

private fun Modifier.heightIn44(): Modifier = this.height(38.dp)

@Composable
private fun TrackList(
    tracks: List<Track>,
    playerState: PlayerUiState,
    bottomPadding: Dp,
    emptyTitle: String,
    emptySubtitle: String,
    showHeader: Boolean,
    onPlayAll: (shuffled: Boolean) -> Unit,
    onPlay: (Int) -> Unit,
    onSongAction: (Track) -> Unit,
) {
    val palette = LocalSonarPalette.current
    val durationText = remember(tracks) {
        val total = tracks.sumOf { it.durationMs ?: 0L }
        if (total <= 0L) null else {
            val minutes = total / 60_000L
            if (minutes >= 60) "约 ${minutes / 60} 小时 ${minutes % 60} 分钟" else "约 $minutes 分钟"
        }
    }
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = bottomPadding + 20.dp),
    ) {
        if (showHeader) {
            item(key = "header") {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 20.dp)
                        .padding(top = 4.dp, bottom = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text("我的收藏", color = palette.ink, fontSize = 28.sp, fontWeight = FontWeight.Bold)
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
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
                    HomePlayButton(
                        title = "播放全部 (${tracks.size})",
                        icon = Icons.Rounded.PlayArrow,
                        primary = true,
                        enabled = tracks.isNotEmpty(),
                        modifier = Modifier.weight(1f),
                    ) { onPlayAll(false) }
                    HomePlayButton(
                        "随机播放",
                        Icons.Rounded.Shuffle,
                        primary = false,
                        enabled = tracks.isNotEmpty(),
                        modifier = Modifier.weight(1f),
                    ) { onPlayAll(true) }
                }
            }
        }
        if (tracks.isEmpty()) {
            item(key = "empty") { EmptyPane(emptyTitle, emptySubtitle) }
        } else {
            itemsIndexed(tracks, key = { _, track -> track.musicId }) { index, track ->
                SongRow(
                    track = track,
                    leading = SongLeading.Index(index + 1),
                    trailing = SongTrailing.More,
                    showAlbum = false,
                    showDivider = index < tracks.lastIndex,
                    isCurrent = playerState.track?.musicId == track.musicId,
                    isPlaying = playerState.isPlaying,
                    onPlay = { onPlay(index) },
                    onAction = { onSongAction(track) },
                )
            }
        }
    }
}

@Composable
private fun HomePlayButton(
    title: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    primary: Boolean,
    modifier: Modifier,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    val palette = LocalSonarPalette.current
    val interaction = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }
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
            val tint = (if (primary) palette.onAccent else palette.ink).copy(alpha = if (enabled) 1f else 0.45f)
            Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(14.dp))
            Spacer(Modifier.size(6.dp))
            Text(
                text = title,
                color = tint,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
            )
        }
    }
}

@Composable
private fun PlaylistRow(
    title: String,
    subtitle: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    onClick: () -> Unit,
) {
    val palette = LocalSonarPalette.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 8.dp, vertical = 8.dp)
            .heightInMin66(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            modifier = Modifier
                .size(50.dp)
                .background(palette.elevated, RoundedCornerShape(8.dp)),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = palette.accent, modifier = Modifier.size(22.dp))
        }
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(title, color = palette.ink, fontSize = 16.sp, fontWeight = FontWeight.Medium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(subtitle, color = palette.secondaryInk, fontSize = 12.sp)
        }
        Icon(Icons.Rounded.ChevronRight, contentDescription = null, tint = palette.tertiaryInk, modifier = Modifier.size(16.dp))
    }
}

private fun Modifier.heightInMin66(): Modifier = this.height(66.dp)

@Composable
private fun ImportButton(
    title: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    modifier: Modifier,
    onClick: () -> Unit,
) {
    val palette = LocalSonarPalette.current
    Row(
        modifier = modifier
            .height(40.dp)
            .background(palette.card, RoundedCornerShape(8.dp))
            .clickable(onClick = onClick),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        Icon(icon, contentDescription = null, tint = palette.ink, modifier = Modifier.size(15.dp))
        Spacer(Modifier.size(6.dp))
        Text(title, color = palette.ink, fontSize = 13.sp, fontWeight = FontWeight.Medium)
    }
}

@Composable
private fun EmptyPane(title: String, subtitle: String) {
    val palette = LocalSonarPalette.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 56.dp, horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(Icons.Rounded.MusicNote, contentDescription = null, tint = palette.tertiaryInk, modifier = Modifier.size(34.dp))
        Text(title, color = palette.ink, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
        Text(subtitle, color = palette.secondaryInk, fontSize = 13.sp)
    }
}
