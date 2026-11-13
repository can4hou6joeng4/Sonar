package cn.bobochang.sonar.ui.player

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.ArrowForward
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Repeat
import androidx.compose.material.icons.rounded.RepeatOne
import androidx.compose.material.icons.rounded.Shuffle
import androidx.compose.material.icons.rounded.SkipNext
import androidx.compose.material.icons.rounded.SkipPrevious
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cn.bobochang.sonar.playback.PlaybackMode
import cn.bobochang.sonar.playback.PlayerUiState
import cn.bobochang.sonar.ui.theme.SonarBaseTextStyle
import cn.bobochang.sonar.ui.theme.bouncePress
import cn.bobochang.sonar.ui.theme.withTnum
import cn.bobochang.sonar.ui.theme.circleIconPress
import cn.bobochang.sonar.ui.theme.AppMotion
import cn.bobochang.sonar.ui.theme.LocalReduceMotion
import kotlin.math.roundToInt

private val PrimaryInk = Color.White.copy(alpha = 0.96f)
private val SecondaryInk = Color.White.copy(alpha = 0.62f)
private val TertiaryInk = Color.White.copy(alpha = 0.34f)
private val ProgressTrack = Color.White.copy(alpha = 0.24f)

/** 对应 iOS `TransportBar`。 */
@Composable
fun TransportBar(
    state: PlayerUiState,
    onToggle: () -> Unit,
    onNext: () -> Unit,
    onPrevious: () -> Unit,
    onSeek: (Long) -> Unit,
    onSetPlaybackMode: (PlaybackMode) -> Unit,
    onRetry: () -> Unit,
) {
    val reduceMotion = LocalReduceMotion.current
    var dragValue by remember { mutableStateOf<Long?>(null) }
    val displayed = dragValue ?: state.positionMs
    val enabled = state.hasTrack
    val hasReachedEnd = state.durationMs > 0 && state.positionMs >= state.durationMs - 250

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .background(Color.White.copy(alpha = 0.07f), RoundedCornerShape(22.dp))
                .border(0.75.dp, Color.White.copy(alpha = 0.14f), RoundedCornerShape(22.dp))
                .padding(horizontal = 14.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                ShuffleButton(
                    enabled = enabled,
                    selected = state.playbackMode == PlaybackMode.SHUFFLE,
                    onClick = {
                        onSetPlaybackMode(
                            if (state.playbackMode == PlaybackMode.SHUFFLE) PlaybackMode.SEQUENCE
                            else PlaybackMode.SHUFFLE,
                        )
                    },
                )
                TransportIcon(
                    icon = Icons.Rounded.SkipPrevious,
                    size = 24.dp,
                    description = "上一首",
                    enabled = enabled,
                    onClick = onPrevious,
                )

                Box(
                    modifier = Modifier.weight(1f),
                    contentAlignment = Alignment.Center,
                ) {
                    val interaction = remember { MutableInteractionSource() }
                    Box(
                        modifier = Modifier
                            .size(66.dp)
                            .then(circleIconPress(interaction, 66.dp, haptic = false))
                            .pointerInput(enabled) {
                                detectTapGestures {
                                    if (!enabled) return@detectTapGestures
                                    if (state.error != null) onRetry()
                                    else onToggle()
                                }
                            },
                        contentAlignment = Alignment.Center,
                    ) {
                        Box(
                            Modifier
                                .size(60.dp)
                                .background(Color.White.copy(alpha = 0.18f), CircleShape)
                                .border(
                                    1.dp,
                                    Brush.linearGradient(
                                        listOf(Color.White.copy(alpha = 0.40f), Color.White.copy(alpha = 0.10f)),
                                    ),
                                    CircleShape,
                                )
                                .shadow(10.dp, CircleShape),
                            contentAlignment = Alignment.Center,
                        ) {
                            when {
                                state.isLoading -> CircularProgressIndicator(
                                    modifier = Modifier.size(24.dp),
                                    color = PrimaryInk,
                                    strokeWidth = 2.dp,
                                )
                                state.error != null -> Icon(
                                    Icons.Rounded.Refresh,
                                    contentDescription = "重试播放",
                                    tint = PrimaryInk,
                                    modifier = Modifier.size(26.dp),
                                )
                                state.isPlaying -> Icon(
                                    Icons.Rounded.Pause,
                                    contentDescription = "暂停",
                                    tint = PrimaryInk,
                                    modifier = Modifier.size(26.dp),
                                )
                                else -> Icon(
                                    Icons.Rounded.PlayArrow,
                                    contentDescription = if (hasReachedEnd) "重新播放" else "播放",
                                    tint = if (enabled) PrimaryInk else TertiaryInk,
                                    modifier = Modifier
                                        .size(30.dp)
                                        .offset(x = 1.5.dp),
                                )
                            }
                        }
                    }
                }

                TransportIcon(
                    icon = Icons.Rounded.SkipNext,
                    size = 24.dp,
                    description = "下一首",
                    enabled = enabled,
                    onClick = onNext,
                )
                RepeatButton(
                    enabled = enabled,
                    mode = state.playbackMode,
                    onClick = {
                        val next = when (state.playbackMode) {
                            PlaybackMode.SEQUENCE, PlaybackMode.SHUFFLE -> PlaybackMode.REPEAT_ONE
                            PlaybackMode.REPEAT_ONE -> PlaybackMode.PLAY_IN_ORDER
                            PlaybackMode.PLAY_IN_ORDER -> PlaybackMode.SEQUENCE
                        }
                        onSetPlaybackMode(next)
                    },
                )
            }

            Column(modifier = Modifier.fillMaxWidth()) {
                PlayerProgressSlider(
                    value = displayed,
                    duration = state.durationMs,
                    onEditing = { dragValue = it },
                    onCommit = {
                        dragValue = null
                        onSeek(it)
                    },
                )
                Row(Modifier.fillMaxWidth()) {
                    Text(
                        text = format(displayed),
                        color = SecondaryInk,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Normal,
                        style = SonarBaseTextStyle.withTnum(),
                    )
                    Spacer(Modifier.weight(1f))
                    Text(
                        text = format(state.durationMs),
                        color = SecondaryInk,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Normal,
                        style = SonarBaseTextStyle.withTnum(),
                    )
                }
            }

            if (state.isLoading || state.error != null) {
                Text(
                    text = if (state.isLoading) "正在连接音频" else "播放失败：${state.error}",
                    color = SecondaryInk,
                    fontSize = 12.sp,
                    fontWeight = FontWeight.Medium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 28.dp)
                        .padding(horizontal = 16.dp),
                )
            }
        }
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.ShuffleButton(enabled: Boolean, selected: Boolean, onClick: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    Box(
        modifier = Modifier
            .weight(1f)
            .heightIn(min = 48.dp)
            .then(bouncePress(interaction, 0.94f, 0.88f, haptic = false))
            .pointerInput(enabled) {
                detectTapGestures { if (enabled) onClick() }
            },
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = Icons.Rounded.Shuffle,
            contentDescription = if (selected) "关闭随机播放" else "随机播放",
            tint = Color.White.copy(alpha = if (selected) 1f else 0.50f),
            modifier = Modifier.size(19.dp),
        )
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.RepeatButton(enabled: Boolean, mode: PlaybackMode, onClick: () -> Unit) {
    val interaction = remember { MutableInteractionSource() }
    Box(
        modifier = Modifier
            .weight(1f)
            .heightIn(min = 48.dp)
            .then(bouncePress(interaction, 0.94f, 0.88f, haptic = false))
            .pointerInput(enabled) {
                detectTapGestures { if (enabled) onClick() }
            },
        contentAlignment = Alignment.Center,
    ) {
        val icon = when (mode) {
            PlaybackMode.REPEAT_ONE -> Icons.Rounded.RepeatOne
            PlaybackMode.PLAY_IN_ORDER -> Icons.Rounded.ArrowForward
            else -> Icons.Rounded.Repeat
        }
        Icon(
            imageVector = icon,
            contentDescription = "播放模式，${mode.title}",
            tint = Color.White.copy(alpha = if (mode == PlaybackMode.SHUFFLE) 0.50f else 1f),
            modifier = Modifier.size(19.dp),
        )
    }
}

@Composable
private fun androidx.compose.foundation.layout.RowScope.TransportIcon(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    size: androidx.compose.ui.unit.Dp,
    description: String,
    enabled: Boolean,
    onClick: () -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    Box(
        modifier = Modifier
            .weight(1f)
            .heightIn(min = 52.dp)
            .then(bouncePress(interaction, 0.88f, 0.82f, haptic = false))
            .pointerInput(enabled) {
                detectTapGestures { if (enabled) onClick() }
            },
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            imageVector = icon,
            contentDescription = description,
            tint = if (enabled) PrimaryInk else TertiaryInk,
            modifier = Modifier.size(size),
        )
    }
}

@Composable
private fun PlayerProgressSlider(
    value: Long,
    duration: Long,
    onEditing: (Long) -> Unit,
    onCommit: (Long) -> Unit,
) {
    var widthPx by remember { mutableFloatStateOf(0f) }
    var dragging by remember { mutableStateOf(false) }
    val density = LocalDensity.current
    val progress = if (duration > 0) (value.toFloat() / duration).coerceIn(0f, 1f) else 0f
    val enabled = duration > 0

    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(44.dp)
            .onSizeChanged { widthPx = it.width.toFloat() }
            .pointerInput(duration) {
                if (!enabled) return@pointerInput
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    dragging = true
                    var last = valueAt(down.position.x, size.width.toFloat(), duration)
                    onEditing(last)
                    while (true) {
                        val event = awaitPointerEvent()
                        val pointer = event.changes.firstOrNull { it.id == down.id } ?: break
                        if (!pointer.pressed) {
                            pointer.consume()
                            break
                        }
                        last = valueAt(pointer.position.x, size.width.toFloat(), duration)
                        onEditing(last)
                        pointer.consume()
                    }
                    dragging = false
                    onCommit(last)
                }
            },
        contentAlignment = Alignment.CenterStart,
    ) {
        val thumbOffset = with(density) { (widthPx * progress).toDp() }
        Box(
            Modifier
                .fillMaxWidth()
                .height(3.dp)
                .background(ProgressTrack, CircleShape),
        )
        Box(
            Modifier
                .fillMaxWidth(progress)
                .height(3.dp)
                .background(PrimaryInk, CircleShape),
        )
        Box(
            Modifier
                .offset(x = (thumbOffset - 5.5.dp).coerceAtLeast(0.dp))
                .size(if (dragging) 16.5.dp else 11.dp)
                .background(Color.White, CircleShape)
                .shadow(2.dp, CircleShape),
        )
    }
}

private fun valueAt(x: Float, width: Float, duration: Long): Long {
    if (width <= 0f || duration <= 0) return 0
    val fraction = (x / width).coerceIn(0f, 1f)
    return (fraction * duration).roundToLongSafely()
}

private fun Float.roundToLongSafely(): Long = roundToInt().toLong().coerceAtLeast(0L)

private fun format(ms: Long): String {
    if (ms <= 0) return "0:00"
    val total = ms / 1000
    return "%d:%02d".format(total / 60, total % 60)
}
