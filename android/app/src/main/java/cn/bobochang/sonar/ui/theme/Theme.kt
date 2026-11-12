package cn.bobochang.sonar.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cn.bobochang.sonar.data.prefs.ThemeMode

/**
 * iOS `M3Scheme.spotlight` 的 Compose 映射。
 * background = appSurface，card = surfaceContainer，elevated = surfaceContainerHigh。
 */
data class SonarPalette(
    val background: Color,
    val card: Color,
    val elevated: Color,
    val ink: Color,
    val secondaryInk: Color,
    val tertiaryInk: Color,
    val divider: Color,
    val accent: Color,
    val onAccent: Color,
    val accentContainer: Color,
    val onAccentContainer: Color,
    val outline: Color,
    val error: Color,
    val inputFill: Color,
    val isDark: Boolean,
)

val DarkPalette = SonarPalette(
    background = Color(0xFF242529),
    card = Color(0xFF303136),
    elevated = Color(0xFF303136),
    ink = Color(0xFFF8F6F2),
    secondaryInk = Color(0xFFB9B8BE),
    tertiaryInk = Color(0xFF77767C),
    divider = Color(0xFF3A3B40),
    accent = Color(0xFFF1E9DF),
    onAccent = Color(0xFF292725),
    accentContainer = Color(0xFF454044),
    onAccentContainer = Color(0xFFF8F6F2),
    outline = Color(0xFF77767C),
    error = Color(0xFFED8B82),
    inputFill = Color(0xFF303136),
    isDark = true,
)

val LightPalette = SonarPalette(
    background = Color(0xFFF4F1EC),
    card = Color(0xFFFFFFFF),
    elevated = Color(0xFFFFFFFF),
    ink = Color(0xFF292725),
    secondaryInk = Color(0xFF73706E),
    tertiaryInk = Color(0xFF9B9793),
    divider = Color(0xFFE0DCD7),
    accent = Color(0xFF51443B),
    onAccent = Color(0xFFFFFFFF),
    accentContainer = Color(0xFFE6DCD1),
    onAccentContainer = Color(0xFF292725),
    outline = Color(0xFF9B9793),
    error = Color(0xFFED8B82),
    inputFill = Color(0xFFFFFFFF),
    isDark = false,
)

val LocalSonarPalette = staticCompositionLocalOf { LightPalette }

/** 跟随系统“移除动画”偏好；与 iOS `sonarReduceMotion` 对应。 */
val LocalReduceMotion = staticCompositionLocalOf { false }

private val DarkColors = darkColorScheme(
    primary = DarkPalette.accent,
    onPrimary = DarkPalette.onAccent,
    primaryContainer = DarkPalette.accentContainer,
    onPrimaryContainer = DarkPalette.onAccentContainer,
    secondary = DarkPalette.accent,
    onSecondary = DarkPalette.onAccent,
    secondaryContainer = DarkPalette.accentContainer,
    onSecondaryContainer = DarkPalette.onAccentContainer,
    background = DarkPalette.background,
    onBackground = DarkPalette.ink,
    surface = DarkPalette.background,
    onSurface = DarkPalette.ink,
    surfaceVariant = DarkPalette.card,
    onSurfaceVariant = DarkPalette.secondaryInk,
    surfaceContainer = DarkPalette.card,
    surfaceContainerHigh = DarkPalette.elevated,
    surfaceContainerHighest = DarkPalette.elevated,
    outline = DarkPalette.outline,
    outlineVariant = DarkPalette.divider,
    error = DarkPalette.error,
    onError = Color.White,
)

private val LightColors = lightColorScheme(
    primary = LightPalette.accent,
    onPrimary = LightPalette.onAccent,
    primaryContainer = LightPalette.accentContainer,
    onPrimaryContainer = LightPalette.onAccentContainer,
    secondary = LightPalette.accent,
    onSecondary = LightPalette.onAccent,
    secondaryContainer = LightPalette.accentContainer,
    onSecondaryContainer = LightPalette.onAccentContainer,
    background = LightPalette.background,
    onBackground = LightPalette.ink,
    surface = LightPalette.background,
    onSurface = LightPalette.ink,
    surfaceVariant = LightPalette.card,
    onSurfaceVariant = LightPalette.secondaryInk,
    surfaceContainer = LightPalette.card,
    surfaceContainerHigh = LightPalette.elevated,
    surfaceContainerHighest = LightPalette.elevated,
    outline = LightPalette.outline,
    outlineVariant = LightPalette.divider,
    error = LightPalette.error,
    onError = Color.White,
)

private val SonarTypography = Typography(
    headlineLarge = TextStyle(fontSize = 30.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.5).sp),
    headlineMedium = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.3).sp),
    headlineSmall = TextStyle(fontSize = 19.sp, fontWeight = FontWeight.SemiBold),
    titleLarge = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.2).sp),
    titleMedium = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.SemiBold),
    titleSmall = TextStyle(fontSize = 15.sp, fontWeight = FontWeight.Medium),
    bodyLarge = TextStyle(fontSize = 16.sp),
    bodyMedium = TextStyle(fontSize = 14.sp),
    bodySmall = TextStyle(fontSize = 12.sp),
    labelLarge = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Medium),
    labelMedium = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.Medium),
    labelSmall = TextStyle(fontSize = 10.sp, fontWeight = FontWeight.Medium),
)

private val SonarShapes = Shapes(
    extraSmall = RoundedCornerShape(6.dp),
    small = RoundedCornerShape(10.dp),
    medium = RoundedCornerShape(14.dp),
    large = RoundedCornerShape(22.dp),
    extraLarge = RoundedCornerShape(28.dp),
)

@Composable
fun SonarTheme(
    themeMode: ThemeMode = ThemeMode.SYSTEM,
    content: @Composable () -> Unit,
) {
    val dark = when (themeMode) {
        ThemeMode.SYSTEM -> isSystemInDarkTheme()
        ThemeMode.DARK -> true
        ThemeMode.LIGHT -> false
    }
    val palette = if (dark) DarkPalette else LightPalette
    CompositionLocalProvider(LocalSonarPalette provides palette) {
        MaterialTheme(
            colorScheme = if (dark) DarkColors else LightColors,
            typography = SonarTypography,
            shapes = SonarShapes,
            content = content,
        )
    }
}
