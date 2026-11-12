package cn.bobochang.sonar.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.FavoriteBorder
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.automirrored.rounded.QueueMusic
import androidx.compose.material.icons.rounded.Repeat
import androidx.compose.material.icons.rounded.RepeatOne
import androidx.compose.material.icons.rounded.Shuffle
import androidx.compose.material.icons.rounded.SkipNext
import androidx.compose.material.icons.rounded.SkipPrevious
import androidx.compose.material.icons.rounded.Subtitles
import androidx.compose.material.icons.automirrored.rounded.VolumeUp
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.core.graphics.drawable.toBitmap
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.palette.graphics.Palette
import cn.bobochang.sonar.data.model.MusicSource
import cn.bobochang.sonar.data.model.Quality
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.data.model.formatDurationMs
import cn.bobochang.sonar.data.prefs.SonarSettings
import cn.bobochang.sonar.di.AppContainer
import cn.bobochang.sonar.lyrics.LrcParser
import cn.bobochang.sonar.lyrics.LyricLine
import cn.bobochang.sonar.playback.PlayerUiState
import cn.bobochang.sonar.ui.components.Artwork
import cn.bobochang.sonar.ui.theme.LocalSonarPalette
import coil.compose.AsyncImage
import coil.imageLoader
import coil.request.ImageRequest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private data class LyricsUiState(
    val lines: List<LyricLine> = emptyList(),
    val loading: Boolean = false,
    val error: String? = null,
)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlayerScreen(
    container: AppContainer,
    onBack: () -> Unit,
    onOpenQueue: () -> Unit,
) {
    val state by container.playerConnection.state.collectAsStateWithLifecycle()
    val sleepMinutes by container.playerConnection.sleepMinutes.collectAsStateWithLifecycle()
    val settings by container.settings.settings.collectAsStateWithLifecycle(initialValue = SonarSettings())
    val palette = LocalSonarPalette.current
    val track = state.track
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val isFavorite by remember(track?.musicId) {
        container.library.observeIsFavorite(track?.musicId ?: "")
    }.collectAsStateWithLifecycle(initialValue = false)
    val queue = remember(state.count, state.index) { container.playerConnection.queue() }
    val currentQuality = remember(state.count, state.index) { container.playerConnection.currentQuality() }
    var accent by remember { mutableStateOf(Color(0xFF3A2226)) }
    var showLyrics by remember { mutableStateOf(false) }
    var showQueue by remember { mutableStateOf(false) }
    var showQuality by remember { mutableStateOf(false) }
    var showMore by remember { mutableStateOf(false) }
    var dragPosition by remember { mutableStateOf<Float?>(null) }

    BackHandler(onBack = onBack)

    val lyricsState by produceState(LyricsUiState(), track?.musicId) {
        val current = track
        if (current == null) {
            value = LyricsUiState()
            return@produceState
        }
        value = LyricsUiState(loading = true)
        value = runCatching {
            val info = container.lyrics.load(current)
            LyricsUiState(lines = container.lyrics.parse(current, info), loading = false)
        }.getOrElse { error ->
            LyricsUiState(loading = false, error = error.message ?: "歌词加载失败")
        }
    }

    LaunchedEffect(track?.coverUrl) {
        val url = track?.coverUrl ?: return@LaunchedEffect
        val request = ImageRequest.Builder(context).data(url).allowHardware(false).build()
        val bitmap = runCatching { context.imageLoader.execute(request).drawable?.toBitmap() }.getOrNull()
            ?: return@LaunchedEffect
        val generated = withContext(Dispatchers.Default) { Palette.from(bitmap).generate() }
        val swatch = generated.vibrantSwatch ?: generated.dominantSwatch ?: generated.mutedSwatch
        swatch?.rgb?.let { accent = Color(it) }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                Brush.verticalGradient(
                    listOf(
                        accent.copy(alpha = 0.78f),
                        Color(0xFF0D0D11),
                        Color(0xFF0D0D11),
                    ),
                ),
            ),
    ) {
        if (track == null) {
            Column(
                modifier = Modifier.fillMaxSize(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Text("还没有正在播放的歌曲", color = palette.secondaryInk)
                TextButton(onClick = onBack) { Text("返回") }
            }
            return@Box
        }

        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 8.dp),
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onBack) {
                    Icon(Icons.Rounded.KeyboardArrowDown, contentDescription = "收起", tint = Color.White)
                }
                Text(
                    text = "正在播放",
                    style = MaterialTheme.typography.titleSmall,
                    color = Color.White.copy(alpha = 0.8f),
                    modifier = Modifier.weight(1f),
                    textAlign = TextAlign.Center,
                )
                IconButton(onClick = {
                    scope.launch { container.library.toggleFavorite(track) }
                }) {
                    Icon(
                        imageVector = if (isFavorite) Icons.Rounded.Favorite else Icons.Rounded.FavoriteBorder,
                        contentDescription = if (isFavorite) "取消收藏" else "收藏",
                        tint = if (isFavorite) palette.accent else Color.White,
                    )
                }
                Box {
                    IconButton(onClick = { showMore = true }) {
                        Icon(Icons.Rounded.MoreVert, contentDescription = "更多", tint = Color.White)
                    }
                    DropdownMenu(expanded = showMore, onDismissRequest = { showMore = false }) {
                        DropdownMenuItem(
                            text = { Text("15 分钟后暂停") },
                            onClick = {
                                showMore = false
                                container.playerConnection.setSleepTimer(15)
                            },
                        )
                        DropdownMenuItem(
                            text = { Text("30 分钟后暂停") },
                            onClick = {
                                showMore = false
                                container.playerConnection.setSleepTimer(30)
                            },
                        )
                        DropdownMenuItem(
                            text = { Text("60 分钟后暂停") },
                            onClick = {
                                showMore = false
                                container.playerConnection.setSleepTimer(60)
                            },
                        )
                        DropdownMenuItem(
                            text = { Text("90 分钟后暂停") },
                            onClick = {
                                showMore = false
                                container.playerConnection.setSleepTimer(90)
                            },
                        )
                        if (sleepMinutes != null) {
                            DropdownMenuItem(
                                text = { Text("取消定时关闭") },
                                onClick = {
                                    showMore = false
                                    container.playerConnection.setSleepTimer(null)
                                },
                            )
                        }
                    }
                }
            }

            Spacer(Modifier.height(18.dp))

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .aspectRatio(1f)
                    .shadow(24.dp, RoundedCornerShape(24.dp), ambientColor = Color.Black, spotColor = Color.Black)
                    .clip(RoundedCornerShape(24.dp))
                    .background(Color(0xFF16161B)),
                contentAlignment = Alignment.Center,
            ) {
                if (track.coverUrl != null) {
                    AsyncImage(
                        model = ImageRequest.Builder(context).data(track.coverUrl).crossfade(true).build(),
                        contentDescription = null,
                        contentScale = ContentScale.Crop,
                        modifier = Modifier.fillMaxSize(),
                    )
                } else {
                    Icon(
                        Icons.Rounded.MusicNote,
                        contentDescription = null,
                        tint = Color.White.copy(alpha = 0.16f),
                        modifier = Modifier.size(88.dp),
                    )
                }
                if (state.isLoading) {
                    CircularProgressIndicator(color = Color.White, modifier = Modifier.size(32.dp))
                }
            }

            Spacer(Modifier.height(22.dp))
            Text(
                text = track.title,
                style = MaterialTheme.typography.headlineMedium.copy(fontWeight = FontWeight.Bold),
                color = Color.White,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.fillMaxWidth(),
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(4.dp))
            Text(
                text = track.artist,
                style = MaterialTheme.typography.bodyMedium,
                color = Color.White.copy(alpha = 0.65f),
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.fillMaxWidth(),
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(8.dp))
            Text(
                text = if (track.source == MusicSource.LOCAL) {
                    "本地文件"
                } else {
                    "${(currentQuality ?: settings.quality).displayName} 音质"
                },
                style = MaterialTheme.typography.labelSmall,
                color = Color.White.copy(alpha = 0.5f),
                modifier = Modifier.fillMaxWidth(),
                textAlign = TextAlign.Center,
            )

            state.error?.let { error ->
                Spacer(Modifier.height(8.dp))
                Text(
                    text = error,
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.accent,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            Spacer(Modifier.height(12.dp))
            val duration = state.durationMs.coerceAtLeast(1L)
            Slider(
                value = (dragPosition ?: state.positionMs.toFloat()).coerceIn(0f, duration.toFloat()),
                onValueChange = { dragPosition = it },
                onValueChangeFinished = {
                    dragPosition?.let { container.playerConnection.seekTo(it.toLong()) }
                    dragPosition = null
                },
                valueRange = 0f..duration.toFloat(),
                colors = SliderDefaults.colors(
                    thumbColor = Color.White,
                    activeTrackColor = Color.White,
                    inactiveTrackColor = Color.White.copy(alpha = 0.24f),
                ),
            )
            Row(modifier = Modifier.fillMaxWidth()) {
                Text(
                    text = formatDurationMs((dragPosition ?: state.positionMs.toFloat()).toLong()),
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.White.copy(alpha = 0.55f),
                )
                Spacer(Modifier.weight(1f))
                Text(
                    text = formatDurationMs(state.durationMs),
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.White.copy(alpha = 0.55f),
                )
            }

            Spacer(Modifier.height(10.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.SpaceEvenly,
            ) {
                IconButton(onClick = { container.playerConnection.toggleShuffle() }) {
                    Icon(
                        Icons.Rounded.Shuffle,
                        contentDescription = "随机播放",
                        tint = if (state.shuffle) palette.accent else Color.White.copy(alpha = 0.7f),
                    )
                }
                IconButton(onClick = { container.playerConnection.previous() }) {
                    Icon(Icons.Rounded.SkipPrevious, contentDescription = "上一首", tint = Color.White, modifier = Modifier.size(34.dp))
                }
                IconButton(
                    onClick = { container.playerConnection.toggle() },
                    modifier = Modifier.size(68.dp),
                    colors = IconButtonDefaults.filledIconButtonColors(
                        containerColor = Color.White,
                        contentColor = Color(0xFF16161B),
                    ),
                ) {
                    Icon(
                        imageVector = if (state.isPlaying) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                        contentDescription = if (state.isPlaying) "暂停" else "播放",
                        modifier = Modifier.size(34.dp),
                    )
                }
                IconButton(onClick = { container.playerConnection.next() }) {
                    Icon(Icons.Rounded.SkipNext, contentDescription = "下一首", tint = Color.White, modifier = Modifier.size(34.dp))
                }
                IconButton(onClick = { container.playerConnection.cycleRepeat() }) {
                    Icon(
                        imageVector = if (state.repeatMode == androidx.media3.common.Player.REPEAT_MODE_ONE) {
                            Icons.Rounded.RepeatOne
                        } else {
                            Icons.Rounded.Repeat
                        },
                        contentDescription = "播放模式",
                        tint = if (state.repeatMode != androidx.media3.common.Player.REPEAT_MODE_OFF) {
                            palette.accent
                        } else {
                            Color.White.copy(alpha = 0.7f)
                        },
                    )
                }
            }

            if (sleepMinutes != null) {
                Text(
                    text = "将在 $sleepMinutes 分钟后暂停",
                    style = MaterialTheme.typography.labelSmall,
                    color = Color.White.copy(alpha = 0.55f),
                    modifier = Modifier.fillMaxWidth(),
                    textAlign = TextAlign.Center,
                )
            }

            Spacer(Modifier.height(14.dp))
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceEvenly,
            ) {
                PlayerAction("歌词", Icons.Rounded.Subtitles) { showLyrics = true }
                PlayerAction("待播", Icons.AutoMirrored.Rounded.QueueMusic) { showQueue = true }
                PlayerAction("音质", Icons.AutoMirrored.Rounded.VolumeUp) { showQuality = true }
            }
            Spacer(Modifier.height(28.dp))
        }
    }

    if (showLyrics) {
        ModalBottomSheet(onDismissRequest = { showLyrics = false }) {
            LyricsSheet(
                state = lyricsState,
                positionMs = state.positionMs,
                offsetMs = settings.lyricsOffsetMs,
                onOffsetChange = { offset ->
                    scope.launch { container.settings.setLyricsOffsetMs(offset) }
                },
            )
        }
    }

    if (showQueue) {
        ModalBottomSheet(onDismissRequest = { showQueue = false }) {
            QueueSheet(
                queue = queue,
                currentIndex = state.index,
                onSelect = { index ->
                    container.playerConnection.playAt(index)
                    showQueue = false
                },
                onRemove = { index -> container.playerConnection.removeAt(index) },
            )
        }
    }

    if (showQuality) {
        ModalBottomSheet(onDismissRequest = { showQuality = false }) {
            QualitySheet(
                selected = settings.quality,
                current = currentQuality,
                isLocal = state.track?.source == MusicSource.LOCAL,
                onSelect = { quality ->
                    scope.launch {
                        container.settings.setQuality(quality)
                        showQuality = false
                    }
                },
            )
        }
    }
}

@Composable
private fun PlayerAction(
    label: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    onClick: () -> Unit,
) {
    Column(
        modifier = Modifier
            .clip(RoundedCornerShape(12.dp))
            .clickable(onClick = onClick)
            .padding(horizontal = 18.dp, vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Icon(icon, contentDescription = null, tint = Color.White.copy(alpha = 0.85f), modifier = Modifier.size(21.dp))
        Text(label, style = MaterialTheme.typography.labelSmall, color = Color.White.copy(alpha = 0.65f))
    }
}

@Composable
private fun LyricsSheet(
    state: LyricsUiState,
    positionMs: Long,
    offsetMs: Long,
    onOffsetChange: (Long) -> Unit,
) {
    val palette = LocalSonarPalette.current
    val listState = rememberLazyListState()
    val adjustedPosition = positionMs + offsetMs
    val currentIndex = LrcParser.indexForTime(state.lines, adjustedPosition)
    LaunchedEffect(currentIndex) {
        if (currentIndex >= 0) {
            listState.animateScrollToItem(currentIndex.coerceAtMost(state.lines.lastIndex))
        }
    }

    Column(modifier = Modifier.fillMaxWidth().fillMaxHeight(0.82f).padding(horizontal = 20.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                "歌词",
                style = MaterialTheme.typography.titleLarge,
                color = palette.ink,
                modifier = Modifier.weight(1f),
            )
            TextButton(onClick = { onOffsetChange(offsetMs - 500) }) { Text("-0.5s") }
            Text(
                "%+.1f s".format(offsetMs / 1000f),
                style = MaterialTheme.typography.labelSmall,
                color = palette.secondaryInk,
            )
            TextButton(onClick = { onOffsetChange(offsetMs + 500) }) { Text("+0.5s") }
        }
        Spacer(Modifier.height(8.dp))
        when {
            state.loading -> Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = palette.accent)
            }

            state.error != null -> Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
                Text(state.error, color = palette.secondaryInk, textAlign = TextAlign.Center)
            }

            state.lines.isEmpty() -> Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
                Text("暂无歌词", color = palette.secondaryInk)
            }

            else -> LazyColumn(state = listState, modifier = Modifier.weight(1f)) {
                itemsIndexed(state.lines) { index, line ->
                    val active = index == currentIndex
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 8.dp),
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Text(
                            text = line.text,
                            style = if (active) {
                                MaterialTheme.typography.titleMedium.copy(fontWeight = FontWeight.SemiBold)
                            } else {
                                MaterialTheme.typography.bodyMedium
                            },
                            color = if (active) palette.accent else palette.secondaryInk,
                            textAlign = TextAlign.Center,
                        )
                        line.translation?.let { translation ->
                            Text(
                                text = translation,
                                style = MaterialTheme.typography.bodySmall,
                                color = if (active) palette.ink.copy(alpha = 0.75f) else palette.tertiaryInk,
                                textAlign = TextAlign.Center,
                            )
                        }
                        line.romanization?.let { romanization ->
                            Text(
                                text = romanization,
                                style = MaterialTheme.typography.labelSmall,
                                color = palette.tertiaryInk,
                                textAlign = TextAlign.Center,
                            )
                        }
                    }
                }
                item { Spacer(Modifier.height(40.dp)) }
            }
        }
    }
}

@Composable
private fun QueueSheet(
    queue: List<Track>,
    currentIndex: Int,
    onSelect: (Int) -> Unit,
    onRemove: (Int) -> Unit,
) {
    val palette = LocalSonarPalette.current
    Column(modifier = Modifier.fillMaxWidth().heightIn(max = 560.dp).padding(horizontal = 16.dp)) {
        Text(
            "待播队列 · ${queue.size} 首",
            style = MaterialTheme.typography.titleLarge,
            color = palette.ink,
            modifier = Modifier.padding(vertical = 12.dp),
        )
        if (queue.isEmpty()) {
            Box(Modifier.fillMaxWidth().height(160.dp), contentAlignment = Alignment.Center) {
                Text("队列为空", color = palette.secondaryInk)
            }
        } else {
            LazyColumn(modifier = Modifier.fillMaxWidth().heightIn(max = 480.dp)) {
                itemsIndexed(queue, key = { index, track -> "$index-${track.musicId}" }) { index, track ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onSelect(index) }
                            .background(
                                if (index == currentIndex) palette.accent.copy(alpha = 0.10f) else Color.Transparent,
                                RoundedCornerShape(10.dp),
                            )
                            .padding(horizontal = 8.dp, vertical = 8.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Artwork(url = track.coverUrl, size = 44.dp, corner = 8.dp)
                        Spacer(Modifier.size(10.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = track.title,
                                style = MaterialTheme.typography.titleSmall,
                                color = if (index == currentIndex) palette.accent else palette.ink,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                            Text(
                                text = track.artist,
                                style = MaterialTheme.typography.bodySmall,
                                color = palette.secondaryInk,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                        TextButton(onClick = { onRemove(index) }) { Text("移除") }
                    }
                }
            }
        }
    }
}

@Composable
private fun QualitySheet(
    selected: Quality,
    current: Quality?,
    isLocal: Boolean,
    onSelect: (Quality) -> Unit,
) {
    val palette = LocalSonarPalette.current
    Column(modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp)) {
        Text("播放音质", style = MaterialTheme.typography.titleLarge, color = palette.ink)
        Text(
            if (isLocal) {
                "本地文件不经过音质选择，修改后对下一首在线歌曲生效。"
            } else {
                "当前实际播放：${current?.displayName ?: selected.displayName}。修改后对下一首生效。"
            },
            style = MaterialTheme.typography.bodySmall,
            color = palette.secondaryInk,
            modifier = Modifier.padding(vertical = 8.dp),
        )
        Quality.entries.reversed().forEach { quality ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(10.dp))
                    .clickable { onSelect(quality) }
                    .background(
                        if (selected == quality) palette.accent.copy(alpha = 0.10f) else Color.Transparent,
                    )
                    .padding(horizontal = 12.dp, vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    quality.displayName,
                    style = MaterialTheme.typography.titleSmall,
                    color = if (selected == quality) palette.accent else palette.ink,
                    modifier = Modifier.weight(1f),
                )
                if (selected == quality) {
                    Text("当前选择", style = MaterialTheme.typography.labelSmall, color = palette.accent)
                }
            }
        }
        Spacer(Modifier.height(20.dp))
    }
}
