package cn.bobochang.sonar.ui.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cn.bobochang.sonar.ui.theme.AppMotion
import cn.bobochang.sonar.ui.theme.LocalSonarPalette
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class ToastController(private val scope: CoroutineScope) {
    var message by mutableStateOf<String?>(null)
        private set

    private var job: Job? = null

    fun show(value: String) {
        job?.cancel()
        message = value
        job = scope.launch {
            delay(1_700)
            message = null
        }
    }
}

val LocalToast = staticCompositionLocalOf<ToastController> {
    error("ToastController not provided")
}

@Composable
fun ProvideToast(controller: ToastController, content: @Composable () -> Unit) {
    CompositionLocalProvider(LocalToast provides controller, content = content)
}

/** iOS `ToastOverlay`：13sp medium，胶囊，高 44。 */
@Composable
fun ToastOverlay(controller: ToastController, modifier: Modifier = Modifier) {
    val palette = LocalSonarPalette.current
    Box(modifier, contentAlignment = Alignment.BottomCenter) {
        AnimatedVisibility(
            visible = controller.message != null,
            enter = fadeIn(tween(AppMotion.SHORT, easing = AppMotion.emphasized)) +
                slideInVertically(tween(AppMotion.SHORT, easing = AppMotion.emphasized)) { it / 2 },
            exit = fadeOut(tween(AppMotion.SHORT)) +
                slideOutVertically(tween(AppMotion.SHORT)) { it / 2 },
        ) {
            val message = controller.message ?: ""
            Text(
                text = message,
                modifier = Modifier
                    .shadow(12.dp, CircleShape)
                    .background(palette.elevated, CircleShape)
                    .padding(horizontal = 18.dp)
                    .heightIn(min = 44.dp),
                color = palette.ink,
                fontSize = 13.sp,
                fontWeight = FontWeight.Medium,
                lineHeight = 44.sp,
            )
        }
    }
}
