package cn.bobochang.sonar.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import cn.bobochang.sonar.ui.theme.LocalReduceMotion
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.sin
import androidx.compose.runtime.withFrameNanos

/** iOS `PlayingEqualizer`：三根 2dp 胶囊，按正弦波起伏。 */
@Composable
fun PlayingEqualizer(
    isAnimating: Boolean,
    color: Color,
    modifier: Modifier = Modifier,
) {
    val reduceMotion = LocalReduceMotion.current
    val heights = remember { mutableFloatStateOf(0f) }
    var phase by remember { mutableFloatStateOf(0f) }

    LaunchedEffect(isAnimating, reduceMotion) {
        if (!isAnimating || reduceMotion) {
            phase = 0f
            return@LaunchedEffect
        }
        val startedAt = System.nanoTime()
        while (isActive) {
            withFrameNanos { }
            phase = (System.nanoTime() - startedAt) / 1_000_000_000f
        }
    }

    Row(
        modifier = modifier
            .size(width = 9.dp, height = 11.dp)
            .then(if (isAnimating && !reduceMotion) Modifier else Modifier),
        horizontalArrangement = Arrangement.spacedBy(1.5.dp),
        verticalAlignment = Alignment.Bottom,
    ) {
        val staticHeights = listOf(5f, 10f, 7f)
        val base = listOf(3.3f, 4.0f, 3.3f)
        val range = listOf(7.7f, 7.0f, 7.7f)
        val phases = listOf(0f, 2.1f, 4.2f)
        for (index in 0..2) {
            val height = if (isAnimating && !reduceMotion) {
                val wave = (sin(phase / 0.9f * 2 * PI.toFloat() + phases[index]) + 1) / 2
                base[index] + range[index] * wave
            } else {
                staticHeights[index]
            }
            Box(
                Modifier
                    .width(2.dp)
                    .height(height.dp)
                    .clip(RoundedCornerShape(1.dp))
                    .background(color),
            )
        }
    }
}
