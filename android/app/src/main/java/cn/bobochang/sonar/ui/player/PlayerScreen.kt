@file:OptIn(
    androidx.compose.foundation.ExperimentalFoundationApi::class,
    androidx.compose.material3.ExperimentalMaterial3Api::class,
)

package cn.bobochang.sonar.ui.player

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.FavoriteBorder
import androidx.compose.material.icons.rounded.FormatQuote
import androidx.compose.material.icons.rounded.KeyboardArrowDown
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material.icons.rounded.QueueMusic
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import cn.bobochang.sonar.data.model.LyricInfo
import cn.bobochang.sonar.data.model.title
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.di.AppContainer
import cn.bobochang.sonar.lyrics.KaraokeLyrics
import cn.bobochang.sonar.playback.PlaybackMode
import cn.bobochang.sonar.playback.PlayerUiState
import cn.bobochang.sonar.ui.components.LocalToast
import cn.bobochang.sonar.ui.components.PlayerArtwork
import cn.bobochang.sonar.ui.theme.LocalReduceMotion
import cn.bobochang.sonar.ui.theme.SonarBaseTextStyle
import cn.bobochang.sonar.ui.theme.bouncePress
import cn.bobochang.sonar.ui.theme.circleIconPress
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

private val PrimaryInk = Color.White.copy(alpha = 0.96f)
private val SecondaryInk = Color.White.copy(alpha = 0.62f)
private val TertiaryInk = Color.White.copy(alpha = 0.34f)

enum class PlayerSurface(val title: String) {
    ARTWORK("封面"),
    LYRICS("歌词"),
    QUEUE("待播放"),
}

private enum class PlayerSheet { COVER, QUALITY }

@Composable
fun PlayerScreen(
    context: android.content.Context,
    container: AppContainer,
    settings: cn.bobochang.sonar.data.prefs.SonarSettings,
    state: PlayerUiState,
    surface: PlayerSurface,
    onSurfaceChange: (PlayerSurface) -> Unit,
    onClose: () -> Unit,
    onDismissDrag: (Float) -> Unit,
    onDismissRelease: (velocityY: Float) -> Unit,
) {
    val toast = LocalToast.current
    val scope = rememberCoroutineScope()
    val reduceMotion = LocalReduceMotion.current
    val track = state.track
    val hue = rememberArtworkHue(track, settings.coverAccentEnabled)

    var sheet by remember { mutableStateOf<PlayerSheet?>(null) }
    var showSleepOptions by remember { mutableStateOf(false) }
    var showRateOptions by remember { mutableStateOf(false) }
    var lyricsInfo by remember(track?.musicId) { mutableStateOf<LyricInfo?>(null) }
    var lyricsError by remember(track?.musicId) { mutableStateOf<String?>(null) }
    var lyricsOffset by remember(track?.musicId) { mutableFloatStateOf(0f) }
    var isCollected by remember(track?.musicId) { mutableStateOf(false) }
    val sleepRemaining by container.playerConnection.sleepRemainingMs.collectAsStateWithLifecycle()

    LaunchedEffect(track?.musicId) {
        lyricsInfo = null
        lyricsError = null
        if (track == null) return@LaunchedEffect
        lyricsOffset = container.settings.lyricsOffsetSeconds(track.musicId)
        runCatching { container.lyrics.load(track) }
            .onSuccess { lyricsInfo = it }
            .onFailure { lyricsError = it.message ?: "歌词加载失败" }
    }
    LaunchedEffect(track?.musicId) {
        isCollected = track?.let { container.library.isFavorite(it.musicId) } ?: false
    }

    val karaoke = remember(lyricsInfo) { lyricsInfo?.let { container.lyrics.parseKaraoke(it) } ?: KaraokeLyrics() }

    Box(Modifier.fillMaxSize()) {
        FlowingLightBackground(hue = hue, coverAccentEnabled = settings.coverAccentEnabled)
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
            PlayerTopBar(
                surface = surface,
                isCollected = isCollected,
                hasTrack = track != null,
                onClose = {
                    onSurfaceChange(PlayerSurface.ARTWORK)
                    onClose()
                },
                onToggleCollection = {
                    val value = track ?: return@PlayerTopBar
                    scope.launch {
                        val added = container.library.toggleFavorite(value)
                        isCollected = added
                        toast.show(if (added) "已收藏" else "已取消收藏")
                    }
                },
            )

            Box(Modifier.weight(1f).fillMaxWidth()) {
                when (surface) {
                    PlayerSurface.ARTWORK -> Column(Modifier.fillMaxSize()) {
                        AlbumFace(
                            track = track,
                            isPlaying = state.isPlaying,
                            modifier = Modifier
                                .weight(1f)
                                .fillMaxWidth()
                                .pointerInput(Unit) {
                                    awaitEachGesture {
                                        val down = awaitFirstDown(requireUnconsumed = false)
                                        val tracker = VelocityTracker()
                                        tracker.addPosition(down.uptimeMillis, down.position)
                                        var vertical = 0f
                                        var horizontal = 0f
                                        var active = false
                                        while (true) {
                                            val event = awaitPointerEvent()
                                            val change = event.changes.firstOrNull { it.id == down.id } ?: break
                                            tracker.addPosition(change.uptimeMillis, change.position)
                                            if (!change.pressed) break
                                            val delta = change.positionChange()
                                            vertical += delta.y
                                            horizontal += delta.x
                                            if (!active) {
                                                val slop = viewConfiguration.touchSlop
                                                if (kotlin.math.abs(vertical) > slop &&
                                                    kotlin.math.abs(vertical) > kotlin.math.abs(horizontal)
                                                ) {
                                                    active = true
                                                } else if (kotlin.math.abs(horizontal) > slop) {
                                                    break
                                                }
                                            }
                                            if (active) {
                                                change.consume()
                                                onDismissDrag(delta.y)
                                            }
                                        }
                                        if (active) {
                                            onDismissRelease(tracker.calculateVelocity().y)
                                        }
                                    }
                                },
                            onClick = { onSurfaceChange(PlayerSurface.LYRICS) },
                        )
                        PlayerMetadata(track = track, compact = false)
                    }

                    PlayerSurface.LYRICS -> Column(Modifier.fillMaxSize()) {
                        PlayerMetadata(track = track, compact = true)
                        Box(Modifier.weight(1f).fillMaxWidth()) {
                            KaraokeLyricsView(
                                lyrics = karaoke,
                                errorMessage = lyricsError,
                                positionMs = state.positionMs,
                                isPlaying = state.isPlaying,
                                isBuffering = state.isLoading,
                                timeOffsetSeconds = lyricsOffset,
                                isVisible = true,
                                onSeekTo = { container.playerConnection.seekTo(it) },
                            )
                        }
                    }

                    PlayerSurface.QUEUE -> QueueFace(
                        state = state,
                        onSelect = { container.playerConnection.selectQueueItem(it) },
                        onRemove = { container.playerConnection.removeQueueItem(it) },
                        onClearUpcoming = { container.playerConnection.clearUpcoming() },
                        onMove = { from, insertion -> container.playerConnection.moveQueueItems(from, insertion) },
                        onToggle = { container.playerConnection.toggle() },
                        onRetry = { container.playerConnection.retry() },
                    )
                }
            }

            TransportBar(
                state = state,
                onToggle = { container.playerConnection.toggle() },
                onNext = { container.playerConnection.next() },
                onPrevious = { container.playerConnection.previous() },
                onSeek = { container.playerConnection.seekTo(it) },
                onSetPlaybackMode = { mode -> container.playerConnection.setPlaybackMode(mode) },
                onRetry = { container.playerConnection.retry() },
            )

            PlayerFooter(
                selected = surface,
                enabled = track != null,
                onLyrics = {
                    onSurfaceChange(if (surface == PlayerSurface.LYRICS) PlayerSurface.ARTWORK else PlayerSurface.LYRICS)
                },
                onQueue = {
                    onSurfaceChange(if (surface == PlayerSurface.QUEUE) PlayerSurface.ARTWORK else PlayerSurface.QUEUE)
                },
                onMore = { if (track != null) sheet = PlayerSheet.COVER },
                modifier = Modifier.padding(top = 8.dp, bottom = 8.dp),
            )
        }
    }

    when (sheet) {
        PlayerSheet.COVER -> ModalBottomSheet(
            onDismissRequest = { sheet = null },
            containerColor = androidx.compose.material3.MaterialTheme.colorScheme.surface,
        ) {
            val current = track ?: return@ModalBottomSheet
            CoverActionsSheet(
                track = current,
                isCollected = isCollected,
                sleepRemainingMs = sleepRemaining,
                playbackRate = state.playbackRate,
                qualityTitle = settings.quality.title,
                onAddToQueue = {
                    scope.launch {
                        container.playerConnection.enqueue(current, settings.quality)
                        toast.show("已加入待播放")
                    }
                },
                onToggleCollection = {
                    scope.launch {
                        val added = container.library.toggleFavorite(current)
                        isCollected = added
                        toast.show(if (added) "已收藏" else "已取消收藏")
                    }
                },
                onSleepTimer = { showSleepOptions = true },
                onPlaybackRate = { showRateOptions = true },
                onShareLyrics = {
                    scope.launch {
                        val result = LyricsShareCardRenderer.share(
                            context = context,
                            track = current,
                            lyrics = karaoke,
                            elapsedMs = state.positionMs,
                        )
                        toast.show(if (result) "已生成歌词卡片" else "暂时无法生成歌词卡片")
                    }
                },
                onSelectQuality = {
                    sheet = null
                    scope.launch {
                        delay(if (reduceMotion) 0 else 180)
                        sheet = PlayerSheet.QUALITY
                    }
                },
                onCancel = { sheet = null },
            )
        }

        PlayerSheet.QUALITY -> ModalBottomSheet(
            onDismissRequest = { sheet = null },
            containerColor = androidx.compose.material3.MaterialTheme.colorScheme.surface,
        ) {
            track?.let { current ->
                QualitySheet(
                    track = current,
                    preferredQuality = settings.quality,
                    actualQuality = state.actualQuality,
                    usingCache = state.usingCache,
                    netEase = container.netEase,
                    onApply = { quality ->
                        sheet = null
                        scope.launch {
                            container.settings.setQuality(quality)
                            container.playerConnection.reloadAtQuality(current, quality)
                            toast.show("已切换到 ${quality.title}")
                        }
                    },
                )
            }
        }

        null -> Unit
    }

    if (showSleepOptions) {
        OptionDialog(
            title = "定时关闭",
            options = listOf(15, 30, 60, 90).map { "$it 分钟" to it } +
                listOfNotNull(if (sleepRemaining != null) "关闭定时" to 0 else null),
            onDismiss = { showSleepOptions = false },
            onSelect = { minutes ->
                showSleepOptions = false
                container.playerConnection.setSleepTimer(minutes.takeIf { it > 0 })
                toast.show(if (minutes > 0) "将在 $minutes 分钟后暂停" else "已关闭定时")
            },
        )
    }

    if (showRateOptions) {
        OptionDialog(
            title = "播放速度",
            options = listOf(
                "0.5x" to 0.5f,
                "0.75x" to 0.75f,
                "1x" to 1f,
                "1.25x" to 1.25f,
                "1.5x" to 1.5f,
                "2x" to 2f,
            ),
            onDismiss = { showRateOptions = false },
            onSelect = { rate ->
                showRateOptions = false
                container.playerConnection.setPlaybackRate(rate)
            },
        )
    }
}

@Composable
private fun PlayerTopBar(
    surface: PlayerSurface,
    isCollected: Boolean,
    hasTrack: Boolean,
    onClose: () -> Unit,
    onToggleCollection: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .height(48.dp)
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        IconCircle(
            icon = Icons.Rounded.KeyboardArrowDown,
            description = "收起播放页",
            onClick = onClose,
        )
        Text(
            text = if (surface == PlayerSurface.ARTWORK) "正在播放" else surface.title,
            color = Color.White.copy(alpha = 0.74f),
            fontSize = 12.sp,
            fontWeight = FontWeight.Medium,
            textAlign = TextAlign.Center,
            modifier = Modifier.weight(1f),
        )
        IconCircle(
            icon = if (isCollected) Icons.Rounded.Favorite else Icons.Rounded.FavoriteBorder,
            description = if (isCollected) "取消收藏" else "收藏歌曲",
            onClick = onToggleCollection,
            enabled = hasTrack,
            tint = if (isCollected) Color(0xFFED8B82) else PrimaryInk,
        )
    }
}

@Composable
private fun IconCircle(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    description: String,
    onClick: () -> Unit,
    enabled: Boolean = true,
    tint: Color = PrimaryInk,
) {
    val interaction = remember { MutableInteractionSource() }
    Box(
        modifier = Modifier
            .size(44.dp)
            .then(circleIconPress(interaction, 38.dp))
            .clickable(
                interactionSource = interaction,
                indication = null,
                enabled = enabled,
                onClick = onClick,
            ),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = description,
            tint = if (enabled) tint else TertiaryInk,
            modifier = Modifier.size(20.dp),
        )
    }
}

@Composable
private fun AlbumFace(
    track: Track?,
    isPlaying: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    BoxWithConstraints(
        modifier = modifier,
        contentAlignment = Alignment.Center,
    ) {
        val size = minOf(maxWidth - 48.dp, maxHeight - 24.dp, 336.dp).coerceAtLeast(0.dp)
        val scale = if (isPlaying) 1f else 0.98f
        PlayerArtwork(
            track = track,
            size = size,
            cornerRadius = 12.dp,
            animatesChanges = true,
            modifier = Modifier
                .graphicsLayer {
                    scaleX = scale
                    scaleY = scale
                }
                .shadow(22.dp, RoundedCornerShape(12.dp))
                .border(
                    0.75.dp,
                    Brush.linearGradient(listOf(Color.White.copy(alpha = 0.24f), Color.White.copy(alpha = 0.06f))),
                    RoundedCornerShape(12.dp),
                )
                .clickable(onClick = onClick),
        )
    }
}

@Composable
private fun PlayerMetadata(track: Track?, compact: Boolean) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .padding(top = 8.dp, bottom = if (compact) 8.dp else 26.dp)
            .heightIn(min = if (compact) 60.dp else 88.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (compact) {
            PlayerArtwork(track = track, size = 48.dp, cornerRadius = 6.dp)
        }
        Column(
            modifier = Modifier.weight(1f),
            horizontalAlignment = if (compact) Alignment.Start else Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(if (compact) 4.dp else 7.dp),
        ) {
            Text(
                text = track?.title ?: "暂无播放",
                color = PrimaryInk,
                fontSize = if (compact) 17.sp else 22.sp,
                fontWeight = if (compact) FontWeight.SemiBold else FontWeight.Bold,
                letterSpacing = if (compact) (-0.2).sp else (-0.3).sp,
                style = SonarBaseTextStyle,
                textAlign = if (compact) TextAlign.Start else TextAlign.Center,
                maxLines = if (compact) 1 else 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = track?.artist?.takeIf { it.isNotBlank() } ?: "选择歌曲开始播放",
                color = SecondaryInk,
                fontSize = 15.sp,
                fontWeight = FontWeight.Normal,
                style = SonarBaseTextStyle,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        if (compact) Spacer(Modifier.size(0.dp))
    }
}

@Composable
private fun PlayerFooter(
    selected: PlayerSurface,
    enabled: Boolean,
    onLyrics: () -> Unit,
    onQueue: () -> Unit,
    onMore: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 36.dp),
    ) {
        FooterButton(Icons.Rounded.FormatQuote, "歌词", enabled, selected == PlayerSurface.LYRICS, onLyrics)
        FooterButton(Icons.Rounded.QueueMusic, "待播放", enabled, selected == PlayerSurface.QUEUE, onQueue)
        FooterButton(Icons.Rounded.MoreHoriz, "更多", enabled, false, onMore)
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.FooterButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    enabled: Boolean,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    Box(
        modifier = Modifier
            .weight(1f)
            .heightIn(min = 44.dp)
            .then(bouncePress(interaction, 0.94f, 0.88f, haptic = false))
            .clickable(
                interactionSource = interaction,
                indication = null,
                enabled = enabled,
                onClick = onClick,
            ),
        contentAlignment = Alignment.Center,
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(5.dp),
        ) {
            Icon(
                imageVector = icon,
                contentDescription = title,
                tint = Color.White.copy(alpha = if (selected) 1f else 0.64f),
                modifier = Modifier.size(14.dp),
            )
            Text(
                text = title,
                color = Color.White.copy(alpha = if (selected) 1f else 0.64f),
                fontSize = 12.sp,
                fontWeight = FontWeight.Medium,
            )
        }
    }
}

@Composable
private fun <T> OptionDialog(
    title: String,
    options: List<Pair<String, T>>,
    onDismiss: () -> Unit,
    onSelect: (T) -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column {
                options.forEach { (label, value) ->
                    Text(
                        text = label,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable { onSelect(value) }
                            .padding(vertical = 14.dp),
                        fontSize = 16.sp,
                    )
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onDismiss) { Text("取消") }
        },
    )
}
