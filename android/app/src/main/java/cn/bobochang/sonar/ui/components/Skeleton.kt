package cn.bobochang.sonar.ui.components

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import cn.bobochang.sonar.ui.theme.LocalReduceMotion
import cn.bobochang.sonar.ui.theme.LocalSonarPalette

/** 加载占位块：轻微呼吸动画，对应 iOS `SkeletonBlock`。 */
@Composable
fun SkeletonBlock(
    width: Dp? = null,
    height: Dp = 12.dp,
    cornerRadius: Dp = 6.dp,
) {
    val palette = LocalSonarPalette.current
    val reduceMotion = LocalReduceMotion.current
    val transition = rememberInfiniteTransition(label = "skeleton")
    val alpha by transition.animateFloat(
        initialValue = 1f,
        targetValue = 0.55f,
        animationSpec = infiniteRepeatable(tween(900), RepeatMode.Reverse),
        label = "skeleton-alpha",
    )
    Box(
        Modifier
            .then(if (width != null) Modifier.width(width) else Modifier)
            .height(height)
            .clip(RoundedCornerShape(cornerRadius))
            .background(palette.elevated)
            .alpha(if (reduceMotion) 1f else alpha),
    )
}

@Composable
fun SkeletonSongRow(showsCover: Boolean = true) {
    Row(
        modifier = Modifier
            .padding(horizontal = 16.dp)
            .height(60.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        if (showsCover) {
            SkeletonBlock(width = 44.dp, height = 44.dp, cornerRadius = 6.dp)
        } else {
            SkeletonBlock(width = 26.dp, height = 14.dp, cornerRadius = 4.dp)
        }
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Spacer(Modifier.height(10.dp))
            SkeletonBlock(width = 150.dp, height = 13.dp)
            SkeletonBlock(width = 210.dp, height = 11.dp)
        }
    }
}

@Composable
fun SkeletonSongList(rows: Int = 6, showsCover: Boolean = true) {
    Column {
        repeat(rows) { SkeletonSongRow(showsCover) }
    }
}

@Composable
fun SkeletonCardRow(cards: Int = 3) {
    Row(
        modifier = Modifier.padding(16.dp),
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        repeat(cards) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                SkeletonBlock(width = 100.dp, height = 100.dp, cornerRadius = 8.dp)
                SkeletonBlock(width = 80.dp, height = 10.dp)
            }
        }
        Spacer(Modifier.size(0.dp))
    }
}
