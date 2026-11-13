package cn.bobochang.sonar.ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cn.bobochang.sonar.di.AppContainer
import cn.bobochang.sonar.ui.components.PlayerArtwork
import cn.bobochang.sonar.ui.theme.LocalReduceMotion
import cn.bobochang.sonar.ui.theme.SonarBaseTextStyle
import cn.bobochang.sonar.ui.theme.SonarRoundedFontFamily
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** 对应 iOS `SonarWelcomeView`：黑胶唱片从唱盘上滑出，完成一次品牌入场。 */
@Composable
fun WelcomeView(container: AppContainer, onComplete: () -> Unit) {
    val reduceMotion = LocalReduceMotion.current
    val favorites by container.library.observeFavorites().collectAsState(initial = emptyList())
    val track = favorites.firstOrNull { it.source.isEnabled }

    val coverScale = remember { Animatable(if (reduceMotion) 1f else 0.88f) }
    val coverAlpha = remember { Animatable(if (reduceMotion) 1f else 0f) }
    val discOffset = remember { Animatable(0f) }
    val discRotation = remember { Animatable(-24f) }
    val brandAlpha = remember { Animatable(if (reduceMotion) 1f else 0f) }
    val brandOffset = remember { Animatable(if (reduceMotion) 0f else 16f) }
    val taglineAlpha = remember { Animatable(if (reduceMotion) 1f else 0f) }
    val taglineOffset = remember { Animatable(if (reduceMotion) 0f else 8f) }
    val introAlpha = remember { Animatable(1f) }

    LaunchedEffect(reduceMotion) {
        if (reduceMotion) {
            delay(150)
            onComplete()
            return@LaunchedEffect
        }
        launch {
            coverAlpha.animateTo(1f, tween(550))
        }
        coverScale.animateTo(1f, tween(550))
        delay(420)
        launch {
            discOffset.animateTo(62f, tween(800, easing = CubicBezierEasing(0.22f, 0.7f, 0.18f, 1f)))
        }
        launch {
            discRotation.animateTo(190f, tween(2_500, easing = LinearEasing))
        }
        delay(520)
        launch {
            brandAlpha.animateTo(1f, tween(450))
        }
        brandOffset.animateTo(0f, tween(450))
        delay(160)
        launch {
            taglineAlpha.animateTo(1f, tween(400))
        }
        taglineOffset.animateTo(0f, tween(400))
        delay(900)
        launch {
            discOffset.animateTo(0f, tween(600, easing = CubicBezierEasing(0.4f, 0f, 0.2f, 1f)))
        }
        launch {
            brandAlpha.animateTo(0f, tween(600))
        }
        launch {
            taglineAlpha.animateTo(0f, tween(600))
        }
        introAlpha.animateTo(0f, tween(600))
        delay(650)
        onComplete()
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .graphicsLayer { alpha = introAlpha.value }
            .pointerInput(Unit) {
                awaitPointerEventScope {
                    while (true) {
                        awaitPointerEvent().changes.forEach { it.consume() }
                    }
                }
            }
            .background(
                Brush.verticalGradient(
                    listOf(Color(0xFF91302B), Color(0xFF24121C)),
                ),
            ),
    ) {
        // 中心偏上的红色光晕，对应 iOS 的 RadialGradient。
        Box(
            modifier = Modifier
                .fillMaxSize()
                .drawBehind {
                    val radius = 360.dp.toPx()
                    val center = androidx.compose.ui.geometry.Offset(size.width / 2f, size.height * 0.4f)
                    drawCircle(
                        brush = Brush.radialGradient(
                            colors = listOf(Color.Red.copy(alpha = 0.18f), Color.Transparent),
                            center = center,
                            radius = radius,
                        ),
                        radius = radius,
                        center = center,
                    )
                },
        )
        Column(
            modifier = Modifier.fillMaxSize(),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Box(
                modifier = Modifier
                    .size(180.dp)
                    .graphicsLayer {
                        scaleX = coverScale.value
                        scaleY = coverScale.value
                        alpha = coverAlpha.value
                    },
                contentAlignment = Alignment.Center,
            ) {
                // 唱盘
                Box(
                    modifier = Modifier
                        .size(174.dp)
                        .offset(x = discOffset.value.dp)
                        .rotate(discRotation.value)
                        .background(
                            Brush.sweepGradient(
                                listOf(
                                    Color.Black,
                                    Color(0xFF292929),
                                    Color.Black,
                                    Color(0xFF3B3B3B),
                                    Color.Black,
                                ),
                            ),
                            CircleShape,
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    Canvas(Modifier.fillMaxSize()) {
                        (0 until 7).forEach { index ->
                            val inset = (8 + index * 9).dp.toPx()
                            drawCircle(
                                color = Color.White.copy(alpha = 0.045f),
                                radius = size.minDimension / 2f - inset,
                                style = androidx.compose.ui.graphics.drawscope.Stroke(width = 1.dp.toPx()),
                            )
                        }
                    }
                    PlayerArtwork(track = track, size = 52.dp, circular = true)
                }
                // 封面
                PlayerArtwork(
                    track = track,
                    size = 180.dp,
                    cornerRadius = 9.dp,
                    modifier = Modifier
                        .offset(x = (discOffset.value / 62f * -40f).dp)
                        .shadow(18.dp, androidx.compose.foundation.shape.RoundedCornerShape(9.dp)),
                )
            }
            Spacer(Modifier.height(32.dp))
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    text = "sonar",
                    color = Color.White,
                    fontSize = 52.sp,
                    fontWeight = FontWeight.Black,
                    fontFamily = SonarRoundedFontFamily,
                    letterSpacing = (-2.5).sp,
                    style = SonarBaseTextStyle,
                    modifier = Modifier
                        .graphicsLayer {
                            alpha = brandAlpha.value
                            translationY = brandOffset.value.dp.toPx()
                        },
                )
                Text(
                    text = "在深水里，靠声音辨路。",
                    color = Color.White.copy(alpha = 0.70f),
                    fontSize = 14.sp,
                    fontFamily = FontFamily.Serif,
                    style = SonarBaseTextStyle,
                    modifier = Modifier.graphicsLayer {
                        alpha = taglineAlpha.value
                        translationY = taglineOffset.value.dp.toPx()
                    },
                )
            }
        }
    }
}
