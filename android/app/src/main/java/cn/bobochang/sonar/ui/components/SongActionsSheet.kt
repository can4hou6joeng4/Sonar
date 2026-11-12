@file:OptIn(
    androidx.compose.foundation.ExperimentalFoundationApi::class,
)

package cn.bobochang.sonar.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.FavoriteBorder
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.data.model.highestKnownQuality
import cn.bobochang.sonar.ui.theme.LocalSonarPalette
import cn.bobochang.sonar.ui.theme.cellHighlight

data class SongAction(
    val title: String,
    val icon: ImageVector,
    val destructive: Boolean = false,
    val enabled: Boolean = true,
    val perform: () -> Unit,
)

/** 对应 iOS `SongActionsSheet`：顶部歌曲信息 + 52dp 操作行 + 取消。 */
@Composable
fun SongActionsSheet(
    track: Track,
    actions: List<SongAction>,
    isCollected: Boolean,
    onToggleCollection: () -> Unit,
    onCancel: () -> Unit,
) {
    val palette = LocalSonarPalette.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(palette.background)
            .padding(bottom = 12.dp),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(88.dp)
                .padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            PlayerArtwork(track = track, size = 56.dp, cornerRadius = 8.dp)
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(4.dp),
            ) {
                Text(
                    text = track.title,
                    color = palette.ink,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    if (!track.source.isEnabled) {
                        Text("不可用", color = palette.secondaryInk, fontSize = 9.5.sp, fontWeight = FontWeight.SemiBold)
                    } else if (!track.isPlayable) {
                        Text("已下架", color = palette.secondaryInk, fontSize = 9.5.sp, fontWeight = FontWeight.SemiBold)
                    } else {
                        QualityBadge(track.highestKnownQuality)
                    }
                    Text(
                        text = metadata(track),
                        color = palette.secondaryInk,
                        fontSize = 12.5.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .combinedClickable(
                        interactionSource = remember { MutableInteractionSource() },
                        indication = null,
                        onClick = onToggleCollection,
                    ),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = if (isCollected) Icons.Rounded.Favorite else Icons.Rounded.FavoriteBorder,
                    contentDescription = if (isCollected) "取消收藏" else "收藏歌曲",
                    tint = palette.accent,
                    modifier = Modifier.size(19.dp),
                )
            }
        }

        HorizontalDivider(color = palette.divider, thickness = 0.5.dp)
        actions.forEachIndexed { index, action ->
            val interaction = remember(action.title) { MutableInteractionSource() }
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp)
                    .cellHighlight(interaction)
                    .combinedClickable(
                        interactionSource = interaction,
                        indication = null,
                        enabled = action.enabled,
                        onClick = {
                            if (action.enabled) {
                                action.perform()
                                onCancel()
                            }
                        },
                    )
                    .height(52.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Icon(
                    imageVector = action.icon,
                    contentDescription = null,
                    tint = if (action.destructive) palette.accent
                    else if (action.enabled) palette.ink else palette.secondaryInk.copy(alpha = 0.6f),
                    modifier = Modifier.size(22.dp),
                )
                Text(
                    text = action.title,
                    color = if (action.destructive) palette.accent
                    else if (action.enabled) palette.ink else palette.secondaryInk.copy(alpha = 0.6f),
                    fontSize = 15.5.sp,
                )
                Spacer(Modifier.weight(1f))
            }
            if (index < actions.lastIndex) {
                HorizontalDivider(
                    color = palette.divider,
                    thickness = 0.5.dp,
                    modifier = Modifier.padding(start = 50.dp),
                )
            }
        }

        Spacer(Modifier.height(8.dp))
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .heightIn(min = 50.dp)
                .background(palette.card, RoundedCornerShape(12.dp))
                .combinedClickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    onClick = onCancel,
                ),
            contentAlignment = Alignment.Center,
        ) {
            Text("取消", color = palette.ink, fontSize = 16.sp, fontWeight = FontWeight.Medium)
        }
    }
}

private fun metadata(track: Track): String {
    val album = track.album.trim()
    val parts = buildList {
        if (track.artist.isNotBlank()) add(track.artist)
        if (album.isNotEmpty() && album != track.title) add(album)
    }
    return parts.joinToString(" · ")
}
