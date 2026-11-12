@file:OptIn(
    androidx.compose.foundation.ExperimentalFoundationApi::class,
)

package cn.bobochang.sonar.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.SkipNext
import androidx.compose.material.icons.rounded.SkipPrevious
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cn.bobochang.sonar.playback.PlayerUiState
import cn.bobochang.sonar.ui.theme.LocalSonarPalette
import cn.bobochang.sonar.ui.theme.cellHighlight
import cn.bobochang.sonar.ui.theme.circleIconPress
import kotlin.math.abs

/** iOS `NCMMiniPlayer`：浮在底部导航上方的胶囊播放器。 */
@Composable
fun NcmMiniPlayer(
    state: PlayerUiState,
    onOpen: () -> Unit,
    onOpenQueue: () -> Unit,
    onPlayPause: () -> Unit,
    onNext: () -> Unit,
    onPrevious: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalSonarPalette.current
    val shape = RoundedCornerShape(14.dp)
    val titleInteraction = remember { MutableInteractionSource() }
    val view = LocalView.current
    var dragX by remember { mutableFloatStateOf(0f) }
    val swipeThreshold = with(androidx.compose.ui.platform.LocalDensity.current) { 36.dp.toPx() }
    val progress = if (state.durationMs > 0) {
        (state.positionMs.toFloat() / state.durationMs).coerceIn(0f, 1f)
    } else 0f

    Box(
        modifier = modifier
            .fillMaxWidth()
            .height(62.dp)
            .shadow(14.dp, shape, clip = false)
            .clip(shape)
            .background(palette.card.copy(alpha = 0.70f))
            .border(0.75.dp, palette.ink.copy(alpha = 0.08f), shape)
            .pointerInput(state.track?.musicId) {
                detectDragGestures(
                    onDragEnd = {
                        when {
                            dragX < -swipeThreshold -> onNext()
                            dragX > swipeThreshold -> onPrevious()
                        }
                        dragX = 0f
                    },
                    onDrag = { change, amount ->
                        change.consume()
                        dragX += amount.x
                    },
                )
            },
    ) {
        Row(
            modifier = Modifier
                .fillMaxSize()
                .padding(start = 10.dp, end = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(
                modifier = Modifier
                    .weight(1f)
                    .fillMaxHeight()
                    .cellHighlight(titleInteraction)
                    .combinedClickable(
                        interactionSource = titleInteraction,
                        indication = null,
                        onClick = onOpen,
                        onLongClick = {
                            view.performHapticFeedback(android.view.HapticFeedbackConstants.LONG_PRESS)
                            onOpenQueue()
                        },
                    ),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                PlayerArtwork(
                    track = state.track,
                    size = 44.dp,
                    cornerRadius = 8.dp,
                    animatesChanges = true,
                )
                Column(
                    modifier = Modifier.weight(1f),
                    verticalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Text(
                        text = state.track?.title ?: "暂无播放",
                        color = palette.ink,
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Medium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        text = subtitle(state),
                        color = palette.secondaryInk,
                        fontSize = 11.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }

            MiniControl(icon = Icons.Rounded.SkipPrevious, description = "上一首", onClick = onPrevious, enabled = state.hasTrack)
            MiniPlayPause(state = state, onClick = onPlayPause)
            MiniControl(icon = Icons.Rounded.SkipNext, description = "下一首", onClick = onNext, enabled = state.hasTrack)
        }

        Box(
            Modifier
                .align(Alignment.BottomStart)
                .padding(horizontal = 14.dp)
                .fillMaxWidth(progress)
                .height(2.dp)
                .clip(CircleShape)
                .background(palette.ink.copy(alpha = 0.50f)),
        )
    }
}

@Composable
private fun MiniControl(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    description: String,
    onClick: () -> Unit,
    enabled: Boolean,
) {
    val palette = LocalSonarPalette.current
    val interaction = remember { MutableInteractionSource() }
    Box(
        modifier = Modifier
            .size(44.dp)
            .then(circleIconPress(interaction, 38.dp, haptic = false)),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .fillMaxSize()
                .combinedClickable(interactionSource = interaction, indication = null, onClick = onClick, enabled = enabled),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = description,
                tint = if (enabled) palette.ink else palette.tertiaryInk,
                modifier = Modifier.size(16.dp),
            )
        }
    }
}

@Composable
private fun MiniPlayPause(state: PlayerUiState, onClick: () -> Unit) {
    val palette = LocalSonarPalette.current
    val interaction = remember { MutableInteractionSource() }
    Box(
        modifier = Modifier
            .size(44.dp)
            .then(circleIconPress(interaction, 38.dp, haptic = false)),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            Modifier
                .fillMaxSize()
                .combinedClickable(
                    interactionSource = interaction,
                    indication = null,
                    onClick = onClick,
                    enabled = state.hasTrack,
                ),
            contentAlignment = Alignment.Center,
        ) {
            when {
                state.isLoading -> CircularProgressIndicator(
                    modifier = Modifier.size(24.dp),
                    color = palette.ink,
                    strokeWidth = 2.dp,
                )
                state.error != null -> Icon(
                    Icons.Rounded.Refresh,
                    contentDescription = "重试播放",
                    tint = palette.ink,
                    modifier = Modifier.size(28.dp),
                )
                state.isPlaying -> Icon(
                    Icons.Rounded.Pause,
                    contentDescription = "暂停",
                    tint = palette.ink,
                    modifier = Modifier.size(28.dp),
                )
                else -> Icon(
                    Icons.Rounded.PlayArrow,
                    contentDescription = "播放",
                    tint = if (state.hasTrack) palette.ink else palette.tertiaryInk,
                    modifier = Modifier.size(28.dp),
                )
            }
        }
    }
}

private fun subtitle(state: PlayerUiState): String {
    val artist = state.track?.artist?.takeIf { it.isNotBlank() } ?: "选择歌曲开始播放"
    return when {
        state.isLoading -> "正在加载 · $artist"
        state.error != null -> "播放失败，点按重试"
        else -> artist
    }
}
