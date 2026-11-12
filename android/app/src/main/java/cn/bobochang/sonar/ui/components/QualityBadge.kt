package cn.bobochang.sonar.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cn.bobochang.sonar.data.model.MusicSource
import cn.bobochang.sonar.data.model.Quality
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.data.model.badgeTitle
import cn.bobochang.sonar.data.model.highestKnownQuality
import cn.bobochang.sonar.ui.theme.LocalSonarPalette

/** iOS `QualityBadge`，8.75pt semibold，最小 27×16。 */
@Composable
fun QualityBadge(quality: Quality, modifier: Modifier = Modifier) {
    val palette = LocalSonarPalette.current
    val background = when (quality) {
        Quality.MASTER, Quality.HI_RES -> palette.accentContainer
        Quality.LOSSLESS -> palette.accentContainer.copy(alpha = 0.72f)
        else -> palette.elevated
    }
    val foreground = when (quality) {
        Quality.MASTER, Quality.HI_RES, Quality.LOSSLESS -> palette.onAccentContainer
        else -> palette.secondaryInk
    }
    Text(
        text = quality.badgeTitle,
        modifier = modifier
            .background(background, RoundedCornerShape(6.dp))
            .padding(horizontal = 5.dp)
            .widthIn(min = 27.dp)
            .heightIn(min = 16.dp),
        color = foreground,
        fontSize = 8.75.sp,
        lineHeight = 16.sp,
        fontWeight = FontWeight.SemiBold,
        letterSpacing = 0.08.sp,
    )
}

@Composable
fun QualityBadge(track: Track, modifier: Modifier = Modifier) {
    QualityBadge(track.highestKnownQuality, modifier)
}

@Composable
fun SourceBadge(track: Track, modifier: Modifier = Modifier) {
    if (track.source == MusicSource.WY) return
    val palette = LocalSonarPalette.current
    Text(
        text = track.source.displayName,
        modifier = modifier
            .background(palette.elevated, RoundedCornerShape(6.dp))
            .padding(horizontal = 5.dp)
            .heightIn(min = 16.dp),
        color = palette.secondaryInk,
        fontSize = 8.75.sp,
        lineHeight = 16.sp,
        fontWeight = FontWeight.SemiBold,
    )
}

fun qualityLabelColor(track: Track, palette: cn.bobochang.sonar.ui.theme.SonarPalette): Color =
    if (track.isPlayable) palette.secondaryInk else palette.tertiaryInk
