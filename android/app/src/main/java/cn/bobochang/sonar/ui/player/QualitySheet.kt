package cn.bobochang.sonar.ui.player

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.PersonPin
import androidx.compose.material.icons.rounded.GraphicEq
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cn.bobochang.sonar.data.model.MusicSource
import cn.bobochang.sonar.data.model.Quality
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.data.model.TrackQualityOption
import cn.bobochang.sonar.data.model.title
import cn.bobochang.sonar.data.net.NetEaseWebClient
import cn.bobochang.sonar.ui.components.SheetHeader
import cn.bobochang.sonar.ui.theme.LocalSonarPalette

/** 对应 iOS `QualitySheet`：列出全部档位，展示账号可播上限与实际播放音质。 */
@Composable
fun QualitySheet(
    track: Track,
    preferredQuality: Quality,
    actualQuality: Quality?,
    usingCache: Boolean,
    netEase: NetEaseWebClient,
    onApply: (Quality) -> Unit,
) {
    val palette = LocalSonarPalette.current
    var ceiling by remember(track.musicId) { mutableStateOf<Quality?>(null) }
    val options = remember(track.musicId) {
        TrackQualityOption.available(track).associateBy { it.quality }
    }

    LaunchedEffect(track.musicId) {
        if (track.source != MusicSource.WY) return@LaunchedEffect
        ceiling = runCatching {
            netEase.privileges(listOf(track.songmid))[track.songmid]
                ?.let(Quality::fromNetEaseLevel)
        }.getOrNull()
    }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(palette.background)
            .padding(bottom = 20.dp),
    ) {
        SheetHeader(title = "播放音质", subtitle = track.title)
        LazyColumn(
            modifier = Modifier.fillMaxWidth().heightIn(max = 520.dp),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            ceiling?.let { value ->
                item(key = "ceiling") {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Icon(Icons.Rounded.PersonPin, contentDescription = null, tint = palette.secondaryInk, modifier = Modifier.size(12.dp))
                        Text("账号当前可播上限：${value.title}", color = palette.secondaryInk, fontSize = 12.sp)
                    }
                }
            }
            actualQuality?.let { value ->
                item(key = "actual") {
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Icon(Icons.Rounded.GraphicEq, contentDescription = null, tint = palette.accent, modifier = Modifier.size(12.dp))
                        Text(
                            text = "${if (usingCache) "当前缓存音质" else "上次实际播放音质"}：${value.title}",
                            color = palette.secondaryInk,
                            fontSize = 12.sp,
                        )
                    }
                }
            }
            items(Quality.descending, key = { it.name }) { quality ->
                val option = options[quality]
                val selected = preferredQuality == quality
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .background(
                            if (selected) palette.accentContainer.copy(alpha = 0.72f) else palette.card,
                            RoundedCornerShape(12.dp),
                        )
                        .clickable { onApply(quality) }
                        .padding(horizontal = 16.dp)
                        .heightIn(min = 62.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Column(
                        modifier = Modifier.weight(1f),
                        verticalArrangement = Arrangement.spacedBy(3.dp),
                    ) {
                        Text(quality.title, color = palette.ink, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                        Text(
                            text = option?.let {
                                it.sizeText.takeIf { size -> size.isNotBlank() }?.let { size -> "文件大小 $size" }
                                    ?: "音源标记支持"
                            } ?: "从此档位开始，无法获取时逐级降低",
                            color = palette.secondaryInk,
                            fontSize = 12.5.sp,
                        )
                    }
                    if (selected) {
                        Icon(
                            Icons.Rounded.CheckCircle,
                            contentDescription = null,
                            tint = palette.onAccentContainer,
                            modifier = Modifier.size(22.dp),
                        )
                    }
                }
            }
            item(key = "bottom") { Spacer(Modifier.size(8.dp)) }
        }
    }
}
