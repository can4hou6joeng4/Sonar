package cn.bobochang.sonar.ui.components

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.data.model.string
import cn.bobochang.sonar.ui.theme.LocalSonarPalette
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject

@Composable
fun QualityBadge(track: Track, modifier: Modifier = Modifier) {
    val palette = LocalSonarPalette.current
    val label = remember(track.payload) { qualityLabel(track) } ?: return
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(4.dp),
        color = palette.accent.copy(alpha = 0.16f),
    ) {
        Text(
            text = label,
            color = palette.accent,
            style = MaterialTheme.typography.labelSmall.copy(fontSize = 9.sp),
            modifier = Modifier.padding(horizontal = 4.dp, vertical = 1.dp),
        )
    }
}

@Composable
fun SourceBadge(track: Track, modifier: Modifier = Modifier) {
    val palette = LocalSonarPalette.current
    if (track.source == cn.bobochang.sonar.data.model.MusicSource.WY) return
    Surface(
        modifier = modifier,
        shape = RoundedCornerShape(4.dp),
        color = palette.elevated,
    ) {
        Text(
            text = track.source.displayName,
            color = palette.secondaryInk,
            style = MaterialTheme.typography.labelSmall.copy(fontSize = 9.sp),
            modifier = Modifier.padding(horizontal = 4.dp, vertical = 1.dp),
        )
    }
}

private fun qualityLabel(track: Track): String? {
    val types = track.payload["types"] as? JsonArray ?: return null
    val values = types.mapNotNull { (it as? JsonObject)?.string("type") }.toSet()
    return when {
        "master" in values -> "母带"
        "flac24bit" in values -> "Hi-Res"
        "flac" in values -> "无损"
        "320k" in values -> "320K"
        "128k" in values -> "128K"
        else -> null
    }
}
