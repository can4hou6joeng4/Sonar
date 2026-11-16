@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.rounded.LibraryMusic
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.TextButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.runtime.LaunchedEffect
import cn.bobochang.sonar.data.library.PlaylistFilter
import cn.bobochang.sonar.ui.components.PlaylistFilterButton
import cn.bobochang.sonar.ui.components.PlaylistFilterSummary
import cn.bobochang.sonar.ui.components.FilteredPlaylistEmpty
import kotlinx.coroutines.CancellationException
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.Shuffle
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.di.AppContainer
import cn.bobochang.sonar.playback.PlaybackMode
import cn.bobochang.sonar.playback.PlayerUiState
import cn.bobochang.sonar.ui.components.LocalToast
import cn.bobochang.sonar.ui.components.SongLeading
import cn.bobochang.sonar.ui.components.SongRow
import cn.bobochang.sonar.ui.components.SongTrailing
import cn.bobochang.sonar.ui.theme.LocalSonarPalette
import cn.bobochang.sonar.ui.theme.SonarBaseTextStyle
import cn.bobochang.sonar.ui.theme.bouncePress
import cn.bobochang.sonar.ui.theme.circleIconPress
import cn.bobochang.sonar.ui.theme.withTnum
import kotlinx.coroutines.launch

/**
 * 资料库 Tab 的根页面：直接就是个人收藏歌单的详情，完全复刻 iOS `LibraryPlaylistView`。
 * 不再有任何四段选择器，呈现纯粹的沉浸式“我的收藏”。
 */
@Composable
fun LibraryScreen(
    container: AppContainer,
    playerState: PlayerUiState,
    bottomPadding: Dp,
    onOpenSettings: () -> Unit,
    onOpenPlaylist: (String) -> Unit = {},
    onImportFiles: () -> Unit = {},
    onImportFolder: () -> Unit = {},
    onSongAction: (Track) -> Unit,
) {
    val palette = LocalSonarPalette.current
    val toast = LocalToast.current
    val scope = rememberCoroutineScope()
    val entries by remember { container.library.observeFavoriteEntries() }.collectAsState(initial = emptyList())
    var filter by remember { mutableStateOf(PlaylistFilter()) }
    val favorites = remember(entries, filter) { filter.apply(entries).map { it.track } }
    val playlists by remember { container.library.observePlaylists() }.collectAsState(initial = emptyList())
    var showPlaylists by remember { mutableStateOf(false) }
    var newPlaylistName by remember { mutableStateOf("") }
    var playlistError by remember { mutableStateOf<String?>(null) }
    val statusTop = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()

    var isSelecting by remember { mutableStateOf(false) }
    var selectedIds by remember { mutableStateOf(setOf<String>()) }
    val visibleIds = favorites.map { it.musicId }.toSet()
    val visibleSelectedIds = selectedIds.intersect(visibleIds)
    LaunchedEffect(visibleIds) { selectedIds = selectedIds.intersect(visibleIds) }

    val durationText = remember(favorites) {
        val total = favorites.sumOf { it.durationMs ?: 0L }
        if (total <= 0L) null else {
            val minutes = total / 60_000L
            if (minutes >= 60) "约 ${minutes / 60} 小时 ${minutes % 60} 分钟" else "约 $minutes 分钟"
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.background)
            .padding(top = statusTop),
    ) {
        // 顶部 NavigationBar：高 44dp，左侧齿轮设置，右侧选择/取消
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(44.dp)
                .padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            val interaction = remember { MutableInteractionSource() }
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .then(circleIconPress(interaction, 38.dp))
                    .clickable(interactionSource = interaction, indication = null, onClick = onOpenSettings),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = Icons.Rounded.Settings,
                    contentDescription = "设置",
                    tint = palette.ink,
                    modifier = Modifier.size(19.dp),
                )
            }

            Spacer(Modifier.weight(1f))
            androidx.compose.material3.IconButton(onClick = { showPlaylists = true }) {
                Icon(Icons.Rounded.LibraryMusic, contentDescription = "我的歌单", tint = palette.ink, modifier = Modifier.size(21.dp))
            }
            PlaylistFilterButton(entries, filter, onChange = { filter = it; selectedIds = emptySet() })

            if (entries.isNotEmpty()) {
                val selectInteraction = remember { MutableInteractionSource() }
                Box(
                    modifier = Modifier
                        .height(44.dp)
                        .clickable(interactionSource = selectInteraction, indication = null) {
                            if (isSelecting) {
                                isSelecting = false
                                selectedIds = emptySet()
                            } else {
                                isSelecting = true
                            }
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = if (isSelecting) "取消" else "选择",
                        color = palette.ink,
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Normal,
                        style = SonarBaseTextStyle,
                    )
                }
            }
        }

        // 多选操作条（若处于多选态）
        if (isSelecting) {
            SelectionBar(
                allSelected = visibleSelectedIds.size == favorites.size && favorites.isNotEmpty(),
                selectedCount = visibleSelectedIds.size,
                onToggleAll = {
                    selectedIds = if (visibleSelectedIds.size == favorites.size) emptySet() else visibleIds
                },
                onEnqueue = {
                    // 只入队当前筛选后可见且被选中的歌曲。
                    val tracksToEnqueue = favorites.filter { it.musicId in visibleSelectedIds }
                    scope.launch {
                        val quality = container.settings.snapshot().quality
                        tracksToEnqueue.forEach { container.playerConnection.enqueue(it, quality) }
                        toast.show("已将 ${tracksToEnqueue.size} 首歌曲加入待播放")
                        isSelecting = false
                        selectedIds = emptySet()
                    }
                },
                onRemove = {
                    val tracksToRemove = favorites.filter { it.musicId in visibleSelectedIds }
                    scope.launch {
                        try {
                            container.library.removeFavorites(tracksToRemove.map { it.musicId })
                            toast.show("已从我的收藏中移除 ${tracksToRemove.size} 首歌曲")
                            isSelecting = false
                            selectedIds = emptySet()
                        } catch (error: CancellationException) {
                            throw error
                        } catch (error: Exception) {
                            toast.show("移除失败：${error.message ?: "请稍后重试"}")
                        }
                    }
                },
            )
        }

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(bottom = bottomPadding + 20.dp),
        ) {
            // Header Section：大标题“我的收藏”与元数据
            item(key = "header") {
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp)
                        .padding(top = 4.dp, bottom = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    Text(
                        text = "我的收藏",
                        color = palette.ink,
                        fontSize = 28.sp,
                        fontWeight = FontWeight.Bold,
                        letterSpacing = (-0.5).sp,
                        style = SonarBaseTextStyle,
                    )
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = if (filter.isActive && entries.isNotEmpty()) {
                                "${favorites.size} / ${entries.size} 首歌曲"
                            } else {
                                "${favorites.size} 首歌曲"
                            },
                            color = palette.secondaryInk,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Medium,
                            style = SonarBaseTextStyle.withTnum(),
                        )
                        if (durationText != null) {
                            Text(
                                text = "·",
                                color = palette.secondaryInk,
                                fontSize = 14.sp,
                                style = SonarBaseTextStyle,
                            )
                            Text(
                                text = durationText,
                                color = palette.secondaryInk,
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Medium,
                                style = SonarBaseTextStyle.withTnum(),
                            )
                        }
                    }
                }
            }

            item(key = "filter-summary") {
                PlaylistFilterSummary(filter, favorites.size, entries.size) { filter = PlaylistFilter(); selectedIds = emptySet() }
            }

            // Playlist Actions：播放全部与随机播放
            item(key = "actions") {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp)
                        .padding(bottom = 12.dp),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    PlayAllAction(
                        count = favorites.size,
                        enabled = favorites.any { it.source.isEnabled },
                        modifier = Modifier.weight(1f),
                        onClick = {
                            if (favorites.isNotEmpty()) {
                                scope.launch {
                                    val quality = container.settings.snapshot().quality
                                    container.playerConnection.setPlaybackMode(PlaybackMode.SEQUENCE)
                                    container.playerConnection.playTracks(favorites, 0, quality)
                                    toast.show("已开始播放 ${favorites.size} 首歌曲")
                                }
                            }
                        },
                    )
                    ShuffleAction(
                        enabled = favorites.any { it.source.isEnabled },
                        modifier = Modifier.weight(1f),
                        onClick = {
                            if (favorites.isNotEmpty()) {
                                scope.launch {
                                    val quality = container.settings.snapshot().quality
                                    container.playerConnection.setPlaybackMode(PlaybackMode.SHUFFLE)
                                    container.playerConnection.playTracks(favorites.shuffled(), 0, quality)
                                    toast.show(
                                        if (favorites.size == 1) "已开始播放" else "已随机播放 ${favorites.size} 首歌曲",
                                    )
                                }
                            }
                        },
                    )
                }
            }

            // 歌曲列表
            if (favorites.isEmpty() && entries.isNotEmpty() && filter.isActive) {
                item(key = "filtered-empty") { FilteredPlaylistEmpty { filter = PlaylistFilter(); selectedIds = emptySet() } }
            } else if (favorites.isEmpty()) {
                item(key = "empty") {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 56.dp, horizontal = 24.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(10.dp),
                    ) {
                        Icon(
                            imageVector = Icons.Rounded.MusicNote,
                            contentDescription = null,
                            tint = palette.tertiaryInk,
                            modifier = Modifier.size(34.dp),
                        )
                        Text(
                            text = "这个歌单还没有歌曲",
                            color = palette.ink,
                            fontSize = 17.sp,
                            fontWeight = FontWeight.SemiBold,
                            style = SonarBaseTextStyle,
                        )
                        Text(
                            text = "在搜索结果或歌手页面长按歌曲，选择“添加到歌单”，歌曲会保存在这里。",
                            color = palette.secondaryInk,
                            fontSize = 13.sp,
                            style = SonarBaseTextStyle,
                        )
                    }
                }
            } else {
                itemsIndexed(favorites, key = { _, track -> track.musicId }) { index, track ->
                    val isTrackSelected = track.musicId in visibleSelectedIds
                    SongRow(
                        track = track,
                        leading = SongLeading.Index(index + 1),
                        trailing = if (isSelecting) SongTrailing.CollectionStatus(isTrackSelected) else SongTrailing.More,
                        showAlbum = false,
                        showDivider = index < favorites.lastIndex,
                        isCurrent = playerState.track?.musicId == track.musicId,
                        isPlaying = playerState.isPlaying,
                        onPlay = {
                            if (isSelecting) {
                                selectedIds = if (isTrackSelected) selectedIds - track.musicId else selectedIds + track.musicId
                            } else {
                                scope.launch {
                                    val quality = container.settings.snapshot().quality
                                    container.playerConnection.setPlaybackMode(PlaybackMode.SEQUENCE)
                                    container.playerConnection.playTracks(favorites, index, quality)
                                }
                            }
                        },
                        onAction = { onSongAction(track) },
                    )
                }
            }
        }
    }

    if (showPlaylists) {
        ModalBottomSheet(onDismissRequest = { showPlaylists = false }, containerColor = palette.background) {
            Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp).padding(bottom = 24.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("我的歌单", color = palette.ink, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(newPlaylistName, { newPlaylistName = it }, label = { Text("新歌单名称") },
                        singleLine = true, modifier = Modifier.weight(1f))
                    TextButton(onClick = {
                        if (newPlaylistName.isNotBlank()) scope.launch {
                            try {
                                container.library.createPlaylist(newPlaylistName)
                                newPlaylistName = ""
                                playlistError = null
                            } catch (error: CancellationException) {
                                throw error
                            } catch (error: Exception) {
                                playlistError = "创建失败：${error.message ?: "请稍后重试"}"
                            }
                        }
                    }) { Text("创建", color = palette.accent) }
                }
                playlistError?.let { Text(it, color = palette.accent, fontSize = 13.sp) }
                LazyColumn(Modifier.fillMaxWidth().height(320.dp)) {
                    items(playlists, key = { it.id }) { playlist ->
                        Row(Modifier.fillMaxWidth().clickable {
                            showPlaylists = false
                            onOpenPlaylist(playlist.id)
                        }.padding(vertical = 14.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Rounded.LibraryMusic, contentDescription = null, tint = palette.accent,
                                modifier = Modifier.size(20.dp))
                            Text(playlist.name, Modifier.weight(1f).padding(start = 12.dp), color = palette.ink,
                                fontSize = 15.sp, maxLines = 1)
                            Text("打开", color = palette.secondaryInk, fontSize = 13.sp)
                        }
                    }
                }
                if (playlists.isEmpty()) Text("还没有个人歌单", color = palette.secondaryInk, fontSize = 13.sp)
            }
        }
    }
}

/** 对应 iOS `playAllButton`：渐变主色、圆角 10dp、图标 13sp bold、标题 14sp bold、徽章 12sp semibold 0.85 opacity。 */
@Composable
private fun PlayAllAction(
    count: Int,
    enabled: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val palette = LocalSonarPalette.current
    val interaction = remember { MutableInteractionSource() }
    val backgroundBrush = Brush.linearGradient(
        listOf(palette.accent, palette.accent.copy(alpha = 0.88f)),
    )
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
                .background(backgroundBrush, RoundedCornerShape(10.dp))
                .padding(horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center,
        ) {
            val contentAlpha = if (enabled) 1f else 0.45f
            Icon(
                imageVector = Icons.Rounded.PlayArrow,
                contentDescription = null,
                tint = palette.onAccent.copy(alpha = contentAlpha),
                modifier = Modifier.size(13.dp),
            )
            Spacer(Modifier.size(6.dp))
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(
                    text = "播放全部",
                    color = palette.onAccent.copy(alpha = contentAlpha),
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Bold,
                    style = SonarBaseTextStyle,
                )
                if (count > 0) {
                    Text(
                        text = "($count)",
                        color = palette.onAccent.copy(alpha = 0.85f * contentAlpha),
                        fontSize = 12.sp,
                        fontWeight = FontWeight.SemiBold,
                        style = SonarBaseTextStyle.withTnum(),
                    )
                }
            }
        }
    }
}

/** 对应 iOS `shuffleButton`：surfaceContainerHigh 背景、圆角 10dp、图标 13sp bold、标题 14sp semibold。 */
@Composable
private fun ShuffleAction(
    enabled: Boolean,
    modifier: Modifier = Modifier,
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
                .background(palette.elevated, RoundedCornerShape(10.dp))
                .padding(horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center,
        ) {
            val contentAlpha = if (enabled) 1f else 0.45f
            Icon(
                imageVector = Icons.Rounded.Shuffle,
                contentDescription = null,
                tint = palette.ink.copy(alpha = contentAlpha),
                modifier = Modifier.size(13.dp),
            )
            Spacer(Modifier.size(6.dp))
            Text(
                text = "随机播放",
                color = palette.ink.copy(alpha = contentAlpha),
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                style = SonarBaseTextStyle,
            )
        }
    }
}

/** 多选操作栏，对应 iOS `selectionBar`。 */
@Composable
private fun SelectionBar(
    allSelected: Boolean,
    selectedCount: Int,
    onToggleAll: () -> Unit,
    onEnqueue: () -> Unit,
    onRemove: () -> Unit,
) {
    val palette = LocalSonarPalette.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(44.dp)
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            text = if (allSelected) "取消全选" else "全选",
            color = palette.ink,
            fontSize = 14.sp,
            fontWeight = FontWeight.Normal,
            style = SonarBaseTextStyle,
            modifier = Modifier.clickable(onClick = onToggleAll),
        )
        Text(
            text = "已选 $selectedCount",
            color = palette.secondaryInk,
            fontSize = 14.sp,
            fontWeight = FontWeight.Normal,
            style = SonarBaseTextStyle.withTnum(),
        )
        Spacer(Modifier.weight(1f))
        Text(
            text = "入队",
            color = if (selectedCount > 0) palette.ink else palette.secondaryInk.copy(alpha = 0.5f),
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
            style = SonarBaseTextStyle,
            modifier = Modifier.clickable(enabled = selectedCount > 0, onClick = onEnqueue),
        )
        Text(
            text = "移出",
            color = if (selectedCount > 0) palette.accent else palette.secondaryInk.copy(alpha = 0.5f),
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
            style = SonarBaseTextStyle,
            modifier = Modifier.clickable(enabled = selectedCount > 0, onClick = onRemove),
        )
    }
}
