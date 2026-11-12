package cn.bobochang.sonar.ui.player

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.ui.artwork.ArtworkPalette
import cn.bobochang.sonar.ui.theme.AppMotion
import cn.bobochang.sonar.ui.theme.LocalReduceMotion

/** 根据当前封面计算播放页背景色相，对应 iOS `FlowingLightBackground`。 */
@Composable
fun rememberArtworkHue(track: Track?, coverAccentEnabled: Boolean): Float {
    val context = LocalContext.current
    val hueState = remember { mutableFloatStateOf(ArtworkPalette.FALLBACK_HUE) }
    LaunchedEffect(track?.musicId, coverAccentEnabled) {
        hueState.floatValue = if (!coverAccentEnabled || track?.coverUrl.isNullOrBlank()) {
            ArtworkPalette.FALLBACK_HUE
        } else {
            ArtworkPalette.accentHue(context, track.coverUrl) ?: ArtworkPalette.FALLBACK_HUE
        }
    }
    val animated by animateFloatAsState(
        targetValue = hueState.floatValue,
        animationSpec = tween(AppMotion.LONG, easing = AppMotion.emphasized),
        label = "flowing-hue",
    )
    return if (LocalReduceMotion.current) hueState.floatValue else animated
}

@Composable
fun FlowingLightBackground(hue: Float, coverAccentEnabled: Boolean, modifier: Modifier = Modifier) {
    val top = Color.hsv(hue, if (coverAccentEnabled) 0.48f else 0.18f, 0.46f)
    val bottom = Color.hsv(hue, if (coverAccentEnabled) 0.40f else 0.14f, 0.17f)
    Box(
        modifier
            .fillMaxSize()
            .background(Brush.verticalGradient(listOf(top, bottom))),
    )
}
