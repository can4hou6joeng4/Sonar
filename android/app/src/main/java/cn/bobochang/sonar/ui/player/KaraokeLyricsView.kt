package cn.bobochang.sonar.ui.player

import androidx.compose.foundation.background
import androidx.compose.foundation.interaction.collectIsDraggedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.clickable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.LocalDensity
import cn.bobochang.sonar.lyrics.KaraokeLine
import cn.bobochang.sonar.lyrics.KaraokeLyrics
import cn.bobochang.sonar.lyrics.KaraokeToken
import cn.bobochang.sonar.ui.theme.LocalReduceMotion
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import androidx.compose.runtime.withFrameNanos
import kotlin.math.abs

private val PrimaryInk = Color.White.copy(alpha = 0.96f)
private val SecondaryInk = Color.White.copy(alpha = 0.62f)
private val TertiaryInk = Color.White.copy(alpha = 0.34f)

/** 当前句在视口中的纵向位置：0.25 表示居中偏上，下方露出更多即将到来的歌词。 */
private const val LyricAnchorFraction = 0.25f

/** iOS `KaraokeLyricsView`：逐字扫光、自动跟随、用户滚动后 3.5 秒恢复。 */
@Composable
fun KaraokeLyricsView(
    lyrics: KaraokeLyrics,
    errorMessage: String?,
    positionMs: Long,
    isPlaying: Boolean,
    isBuffering: Boolean,
    timeOffsetSeconds: Float,
    isVisible: Boolean,
    onSeekTo: (Long) -> Unit,
    modifier: Modifier = Modifier,
) {
    if (lyrics.lines.isEmpty()) {
        Box(modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Icon(
                    Icons.Rounded.MusicNote,
                    contentDescription = null,
                    tint = TertiaryInk,
                    modifier = Modifier.padding(28.dp).height(34.dp),
                )
                Text(
                    text = errorMessage ?: "暂无歌词",
                    color = TertiaryInk,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                    textAlign = TextAlign.Center,
                )
            }
        }
        return
    }

    val effectivePosition = rememberSmoothPosition(positionMs, isPlaying && !isBuffering && isVisible)
    val effectiveMs = effectivePosition + (timeOffsetSeconds * 1_000).toLong()
    val activeIndex = lyrics.currentIndex(effectiveMs / 1000.0)
    val listState = rememberLazyListState()
    val isDragged by listState.interactionSource.collectIsDraggedAsState()
    val reduceMotion = LocalReduceMotion.current
    var userScrollLocked by remember { mutableStateOf(false) }
    var unlockAt by remember { mutableLongStateOf(0L) }
    var viewportHeightPx by remember { mutableStateOf(0f) }

    LaunchedEffect(isDragged) {
        if (isDragged) {
            userScrollLocked = true
            unlockAt = 0L
        } else if (userScrollLocked) {
            unlockAt = System.currentTimeMillis() + 3_500
        }
    }

    LaunchedEffect(userScrollLocked, unlockAt) {
        if (!userScrollLocked || unlockAt == 0L) return@LaunchedEffect
        val remaining = unlockAt - System.currentTimeMillis()
        if (remaining > 0) delay(remaining)
        userScrollLocked = false
    }

    LaunchedEffect(activeIndex, userScrollLocked, viewportHeightPx, isVisible) {
        if (activeIndex == null || userScrollLocked || !isVisible || viewportHeightPx <= 0f) return@LaunchedEffect
        // 顶部 contentPadding 已预留锚点位置，额外的负偏移会将当前句再次向下推。
        if (reduceMotion) {
            listState.scrollToItem(activeIndex, 0)
        } else {
            listState.animateScrollToItem(activeIndex, 0)
        }
    }

    Column(modifier.fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
        if (lyrics.isSynthesized) {
            Text(
                text = "这首歌没有逐字歌词 · 已按字数合成",
                color = TertiaryInk,
                fontSize = 10.5.sp,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = 24.dp, vertical = 6.dp),
            )
        }

        Box(Modifier.weight(1f).fillMaxWidth()) {
            LazyColumn(
                state = listState,
                modifier = Modifier
                    .fillMaxSize()
                    .onSizeChanged { viewportHeightPx = it.height.toFloat() }
                    .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                    .drawWithContent {
                        drawContent()
                        drawRect(
                            brush = Brush.verticalGradient(
                                0f to Color.Transparent,
                                0.12f to Color.Black,
                                0.88f to Color.Black,
                                1f to Color.Transparent,
                            ),
                            blendMode = BlendMode.DstIn,
                        )
                    },
                contentPadding = PaddingValues(
                    top = with(LocalDensity.current) { (viewportHeightPx * LyricAnchorFraction).toDp() },
                    bottom = with(LocalDensity.current) { (viewportHeightPx * (1f - LyricAnchorFraction)).toDp() },
                ),
                horizontalAlignment = Alignment.CenterHorizontally,
            ) {
                items(lyrics.lines, key = { it.id }) { line ->
                    LyricLineView(
                        line = line,
                        isActive = line.id == activeIndex,
                        activeIndex = activeIndex,
                        effectiveMs = effectiveMs,
                        isPlaying = isPlaying && !isBuffering,
                        onSelect = { onSeekTo((line.startMs - timeOffsetSeconds * 1_000).toLong().coerceAtLeast(0)) },
                    )
                }
            }

            if (userScrollLocked) {
                Box(
                    modifier = Modifier
                        .align(Alignment.BottomCenter)
                        .padding(bottom = 8.dp)
                        .clip(CircleShape)
                        .background(Color.White.copy(alpha = 0.16f))
                        .clickable {
                            userScrollLocked = false
                            unlockAt = 0L
                        }
                        .padding(horizontal = 14.dp)
                        .height(30.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    androidx.compose.foundation.layout.Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Icon(Icons.Rounded.PlayArrow, contentDescription = null, tint = PrimaryInk, modifier = Modifier.height(13.dp))
                        Text("回到当前", color = PrimaryInk, fontSize = 12.sp, fontWeight = FontWeight.Medium)
                    }
                }
            }
        }
    }
}

@Composable
private fun LyricLineView(
    line: KaraokeLine,
    isActive: Boolean,
    activeIndex: Int?,
    effectiveMs: Long,
    isPlaying: Boolean,
    onSelect: () -> Unit,
) {
    val reduceMotion = LocalReduceMotion.current
    val distance = activeIndex?.let { kotlin.math.min(abs(line.id - it), 6) } ?: 0
    val opacity = if (isActive) 1f else maxOf(0.3f, 1f - distance * 0.13f)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onSelect)
            .padding(vertical = 9.dp)
            .alpha(opacity)
            .padding(horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(0.dp),
    ) {
        if (isActive) {
            ActiveTokenLine(line = line, effectiveMs = effectiveMs, sweeping = isPlaying && !reduceMotion)
        } else {
            Text(
                text = line.text,
                color = TertiaryInk,
                fontSize = 16.sp,
                fontWeight = FontWeight.Medium,
                textAlign = TextAlign.Center,
                lineHeight = 22.sp,
            )
        }
        line.translation?.takeIf { it.isNotBlank() }?.let { translation ->
            Text(
                text = translation,
                color = TertiaryInk,
                fontSize = 13.sp,
                textAlign = TextAlign.Center,
                lineHeight = 18.sp,
                modifier = Modifier.padding(top = 8.dp),
            )
        }
        line.romanization?.takeIf { it.isNotBlank() }?.let { romanization ->
            Text(
                text = romanization,
                color = TertiaryInk,
                fontSize = 12.sp,
                textAlign = TextAlign.Center,
                lineHeight = 16.sp,
                modifier = Modifier.padding(top = 8.dp),
            )
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ActiveTokenLine(line: KaraokeLine, effectiveMs: Long, sweeping: Boolean) {
    FlowRow(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.Center,
        verticalArrangement = Arrangement.Center,
    ) {
        val tokens = if (line.tokens.isEmpty()) {
            listOf(KaraokeToken(0, line.text, line.startMs, line.endMs))
        } else {
            line.tokens
        }
        for (token in tokens) {
            val progress = if (sweeping) token.progress(effectiveMs.toDouble()) else if (effectiveMs >= token.endMs) 1f else 0f
            TokenView(token = token, progress = progress.toFloat())
        }
    }
}

@Composable
private fun TokenView(token: KaraokeToken, progress: Float) {
    val base = Color.White.copy(alpha = 0.48f)
    Box {
        Text(
            text = token.text,
            color = base,
            fontSize = 19.sp,
            fontWeight = FontWeight.Bold,
            lineHeight = 26.sp,
        )
        Text(
            text = token.text,
            color = PrimaryInk,
            fontSize = 19.sp,
            fontWeight = FontWeight.Bold,
            lineHeight = 26.sp,
            modifier = Modifier.drawWithContent {
                clipRect(right = size.width * progress.coerceIn(0f, 1f)) {
                    this@drawWithContent.drawContent()
                }
            },
        )
    }
}

/** 按播放状态外推的平滑时间轴（播放中每帧推进）。 */
@Composable
fun rememberSmoothPosition(positionMs: Long, running: Boolean): Long {
    var smooth by remember { mutableLongStateOf(positionMs) }
    LaunchedEffect(positionMs, running) {
        smooth = positionMs
        if (!running) return@LaunchedEffect
        val base = positionMs
        val startedAt = System.nanoTime()
        while (isActive) {
            withFrameNanos { }
            smooth = base + (System.nanoTime() - startedAt) / 1_000_000
        }
    }
    return smooth
}
