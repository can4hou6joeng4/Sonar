package cn.bobochang.sonar.ui.theme

import android.view.HapticFeedbackConstants
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.SpringSpec
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** iOS `AppMotion` 的 Compose 对应实现。 */
object AppMotion {
    const val SHORT = 160
    const val MEDIUM = 300
    const val LONG = 420
    const val QUEUE_REORDER = 160
    const val DISC_ROTATION_SECONDS = 20f
    const val LYRICS_FOLLOW_RESUME_MS = 3_500L

    val emphasized = CubicBezierEasing(0.2f, 0f, 0f, 1f)
    val emphasizedDecelerate = CubicBezierEasing(0.05f, 0.7f, 0.1f, 1f)
    val emphasizedAccelerate = CubicBezierEasing(0.3f, 0f, 0.8f, 0.15f)
    val playerPull = CubicBezierEasing(0.32f, 0.72f, 0f, 1f)

    fun <T> emphasizedSpec(durationMillis: Int = MEDIUM): androidx.compose.animation.core.TweenSpec<T> =
        tween(durationMillis, easing = emphasized)

    val standardSpring: SpringSpec<Float>
        get() = spring(dampingRatio = 0.775f, stiffness = 540f)

    val expressiveSpring: SpringSpec<Float>
        get() = spring(dampingRatio = 0.586f, stiffness = 420f)

    val pressSpring: SpringSpec<Float>
        get() = spring(dampingRatio = 0.65f, stiffness = Spring.StiffnessMediumLow)

    val cellPressSpring: SpringSpec<Float>
        get() = spring(dampingRatio = 0.72f, stiffness = Spring.StiffnessMediumLow)
}

enum class SonarHaptic { LIGHT, MEDIUM, SELECTION }

@Composable
fun performHaptic(type: SonarHaptic) {
    val view = LocalView.current
    val feedback = LocalHapticFeedback.current
    when (type) {
        SonarHaptic.LIGHT -> view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
        SonarHaptic.MEDIUM -> view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
        SonarHaptic.SELECTION -> feedback.performHapticFeedback(HapticFeedbackType.TextHandleMove)
    }
}

/**
 * 按压反馈：scale + alpha + 触感，对应 iOS `BounceButtonStyle`。
 * 传入 [interactionSource] 给 clickable 使用。
 */
@Composable
fun bouncePress(
    interactionSource: MutableInteractionSource,
    scale: Float = 0.94f,
    pressedAlpha: Float = 0.88f,
    haptic: Boolean = true,
): Modifier {
    val reduceMotion = LocalReduceMotion.current
    val pressed by interactionSource.collectIsPressedAsState()
    val animatedScale by animateFloatAsState(
        targetValue = if (pressed && !reduceMotion) scale else 1f,
        animationSpec = AppMotion.pressSpring,
        label = "bounce-scale",
    )
    val animatedAlpha by animateFloatAsState(
        targetValue = if (pressed) pressedAlpha else 1f,
        animationSpec = AppMotion.pressSpring,
        label = "bounce-alpha",
    )
    if (haptic) {
        val trigger = rememberHapticTrigger()
        LaunchedEffect(pressed) {
            if (pressed) trigger(SonarHaptic.LIGHT)
        }
    }
    return Modifier.graphicsLayer {
        scaleX = animatedScale
        scaleY = animatedScale
        alpha = animatedAlpha
    }
}

/**
 * 圆形图标按压：scale 0.90 / alpha 0.80，并在按下时铺一层白色 14% 圆形高光。
 */
@Composable
fun circleIconPress(
    interactionSource: MutableInteractionSource,
    diameter: Dp = 36.dp,
    haptic: Boolean = true,
): Modifier {
    val reduceMotion = LocalReduceMotion.current
    val pressed by interactionSource.collectIsPressedAsState()
    val animatedScale by animateFloatAsState(
        targetValue = if (pressed && !reduceMotion) 0.90f else 1f,
        animationSpec = spring(dampingRatio = 0.62f, stiffness = Spring.StiffnessMediumLow),
        label = "circle-scale",
    )
    val animatedAlpha by animateFloatAsState(
        targetValue = if (pressed) 0.80f else 1f,
        animationSpec = spring(dampingRatio = 0.62f, stiffness = Spring.StiffnessMediumLow),
        label = "circle-alpha",
    )
    if (haptic) {
        val trigger = rememberHapticTrigger()
        LaunchedEffect(pressed) {
            if (pressed) trigger(SonarHaptic.LIGHT)
        }
    }
    return Modifier
        .graphicsLayer {
            scaleX = animatedScale
            scaleY = animatedScale
            alpha = animatedAlpha
        }
        .background(
            color = if (pressed) Color.White.copy(alpha = 0.14f) else Color.Transparent,
            shape = CircleShape,
        )
        .size(diameter)
        .clip(CircleShape)
}

/** 列表行按压：细微缩放 + 白色 8% 圆角高光，对应 iOS `CellHighlightButtonStyle`。 */
fun Modifier.cellHighlight(interactionSource: MutableInteractionSource): Modifier = composed {
    val reduceMotion = LocalReduceMotion.current
    val pressed by interactionSource.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = if (pressed && !reduceMotion) 0.985f else 1f,
        animationSpec = AppMotion.cellPressSpring,
        label = "cell-scale",
    )
    this
        .graphicsLayer {
            scaleX = scale
            scaleY = scale
        }
        .background(
            color = if (pressed) Color.White.copy(alpha = 0.08f) else Color.Transparent,
            shape = RoundedCornerShape(10.dp),
        )
}

@Composable
fun rememberHapticTrigger(): (SonarHaptic) -> Unit {
    val view = LocalView.current
    val feedback = LocalHapticFeedback.current
    val scope = rememberCoroutineScopeCompat()
    return remember(view, feedback) {
        { type ->
            when (type) {
                SonarHaptic.LIGHT -> view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                SonarHaptic.MEDIUM -> view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                SonarHaptic.SELECTION -> feedback.performHapticFeedback(HapticFeedbackType.TextHandleMove)
            }
        }
    }
}

@Composable
private fun rememberCoroutineScopeCompat() = androidx.compose.runtime.rememberCoroutineScope()

/** 延迟触觉反馈工具：用于“长按才触发”的场景。 */
@Composable
fun longPressHaptic(delayMillis: Long = 320L): () -> Unit {
    val trigger = rememberHapticTrigger()
    val view = LocalView.current
    return remember(view) {
        {
            trigger(SonarHaptic.MEDIUM)
        }
    }
}

/** 等待若干毫秒的可取消辅助（用于入场序列）。 */
suspend fun pause(ms: Long) {
    delay(ms)
}

/** 将 Animatable 直接驱动到目标值。 */
suspend fun Animatable<Float, *>.snapOrAnimateTo(
    target: Float,
    durationMillis: Int = AppMotion.MEDIUM,
    easing: androidx.compose.animation.core.Easing = AppMotion.emphasized,
) {
    animateTo(target, tween(durationMillis, easing = easing))
}
