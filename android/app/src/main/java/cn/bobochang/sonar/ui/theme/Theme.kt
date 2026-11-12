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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cn.bobochang.sonar.data.prefs.ThemeMode

data class SonarPalette(
    val background: Color,
    val card: Color,
    val elevated: Color,
    val ink: Color,
    val secondaryInk: Color,
    val tertiaryInk: Color,
    val divider: Color,
    val accent: Color,
)

val DarkPalette = SonarPalette(
    background = Color(0xFF0D0D11),
    card = Color(0xFF1B1B1F),
    elevated = Color(0xFF202025),
    ink = Color(0xFFF3F3F3),
    secondaryInk = Color(0xFF858587),
    tertiaryInk = Color(0xFF55555E),
    divider = Color(0xFF232327),
    accent = Color(0xFFFF3A39),
)

val LightPalette = SonarPalette(
    background = Color(0xFFF5F7FB),
    card = Color(0xFFFFFFFF),
    elevated = Color(0xFFF0F1F5),
    ink = Color(0xFF0C0C23),
    secondaryInk = Color(0xFF838190),
    tertiaryInk = Color(0xFFB6B6C0),
    divider = Color(0xFFE8E8EE),
    accent = Color(0xFFFF3738),
)

val LocalSonarPalette = staticCompositionLocalOf { DarkPalette }

private val DarkColors = darkColorScheme(
    primary = DarkPalette.accent,
    onPrimary = Color.White,
    primaryContainer = Color(0xFF5A1F20),
    onPrimaryContainer = Color.White,
    secondary = DarkPalette.accent,
    onSecondary = Color.White,
    background = DarkPalette.background,
    onBackground = DarkPalette.ink,
    surface = DarkPalette.background,
    onSurface = DarkPalette.ink,
    surfaceVariant = DarkPalette.card,
    onSurfaceVariant = DarkPalette.secondaryInk,
    surfaceContainer = DarkPalette.card,
    surfaceContainerHigh = DarkPalette.elevated,
    surfaceContainerHighest = DarkPalette.elevated,
    outline = DarkPalette.tertiaryInk,
    outlineVariant = DarkPalette.divider,
    error = DarkPalette.accent,
    onError = Color.White,
)

private val LightColors = lightColorScheme(
    primary = LightPalette.accent,
    onPrimary = Color.White,
    primaryContainer = Color(0xFFFFE3E3),
    onPrimaryContainer = LightPalette.ink,
    secondary = LightPalette.accent,
    onSecondary = Color.White,
    background = LightPalette.background,
    onBackground = LightPalette.ink,
    surface = LightPalette.background,
    onSurface = LightPalette.ink,
    surfaceVariant = LightPalette.card,
    onSurfaceVariant = LightPalette.secondaryInk,
    surfaceContainer = LightPalette.card,
    surfaceContainerHigh = LightPalette.elevated,
    surfaceContainerHighest = LightPalette.elevated,
    outline = LightPalette.tertiaryInk,
    outlineVariant = LightPalette.divider,
    error = LightPalette.accent,
    onError = Color.White,
)

private val SonarTypography = Typography(
    headlineLarge = TextStyle(fontSize = 30.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.5).sp),
    headlineMedium = TextStyle(fontSize = 24.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.3).sp),
    titleLarge = TextStyle(fontSize = 20.sp, fontWeight = FontWeight.SemiBold),
    titleMedium = TextStyle(fontSize = 16.sp, fontWeight = FontWeight.SemiBold),
    titleSmall = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.Medium),
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
    large = RoundedCornerShape(20.dp),
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
