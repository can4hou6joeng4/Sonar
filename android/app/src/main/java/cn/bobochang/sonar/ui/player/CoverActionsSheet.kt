package cn.bobochang.sonar.ui.player

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.AddCircle
import androidx.compose.material.icons.rounded.Bedtime
import androidx.compose.material.icons.rounded.FavoriteBorder
import androidx.compose.material.icons.rounded.FormatQuote
import androidx.compose.material.icons.rounded.HeartBroken
import androidx.compose.material.icons.rounded.Speed
import androidx.compose.material.icons.rounded.Tune
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.ui.components.SheetHeader
import cn.bobochang.sonar.ui.theme.LocalSonarPalette

/** 对应 iOS `CoverActionsSheet`：播放器“更多”面板。 */
@Composable
fun CoverActionsSheet(
    track: Track,
    isCollected: Boolean,
    sleepRemainingMs: Long?,
    playbackRate: Float,
    qualityTitle: String,
    onAddToQueue: () -> Unit,
    onToggleCollection: () -> Unit,
    onSleepTimer: () -> Unit,
    onPlaybackRate: () -> Unit,
    onShareLyrics: () -> Unit,
    onSelectQuality: () -> Unit,
    onCancel: () -> Unit,
) {
    val palette = LocalSonarPalette.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(palette.background)
            .padding(bottom = 20.dp),
    ) {
        SheetHeader(title = track.title, subtitle = "$qualityTitle · ${track.artist}")
        Column(
            modifier = Modifier.padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            ActionRow(
                icon = Icons.Rounded.AddCircle,
                title = "加入待播放",
                subtitle = "将当前歌曲添加到待播放末尾",
                enabled = track.source.isEnabled,
                onClick = onAddToQueue,
            )
            ActionRow(
                icon = if (isCollected) Icons.Rounded.HeartBroken else Icons.Rounded.FavoriteBorder,
                title = if (isCollected) "移出我的收藏" else "收藏到我的收藏",
                subtitle = if (isCollected) "从个人歌单移除，当前播放不会中断" else "将当前歌曲保存到个人歌单",
                onClick = onToggleCollection,
            )
            ActionRow(
                icon = Icons.Rounded.Bedtime,
                title = "定时关闭",
                subtitle = sleepRemainingMs?.let { formatRemaining(it) } ?: "播放到设定时间后自动暂停",
                onClick = onSleepTimer,
            )
            ActionRow(
                icon = Icons.Rounded.Speed,
                title = "播放速度",
                subtitle = rateLabel(playbackRate),
                onClick = onPlaybackRate,
            )
            ActionRow(
                icon = Icons.Rounded.FormatQuote,
                title = "分享歌词卡片",
                subtitle = "生成一张带歌词的图片分享出去",
                onClick = onShareLyrics,
            )
            ActionRow(
                icon = Icons.Rounded.Tune,
                title = "切换播放音质",
                subtitle = "选择当前歌曲的其他可用音质",
                enabled = track.source.isEnabled,
                onClick = onSelectQuality,
            )
        }
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(top = 8.dp)
                .heightIn(min = 50.dp)
                .background(palette.card, RoundedCornerShape(12.dp))
                .clickable(onClick = onCancel),
            contentAlignment = Alignment.Center,
        ) {
            Text("取消", color = palette.ink, fontSize = 16.sp, fontWeight = FontWeight.Medium)
        }
    }
}

@Composable
private fun ActionRow(
    icon: ImageVector,
    title: String,
    subtitle: String,
    onClick: () -> Unit,
    enabled: Boolean = true,
) {
    val palette = LocalSonarPalette.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(palette.card, RoundedCornerShape(20.dp))
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 16.dp)
            .heightIn(min = 64.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Box(
            modifier = Modifier
                .size(36.dp)
                .background(palette.accentContainer, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = palette.onAccentContainer, modifier = Modifier.size(18.dp))
        }
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(3.dp),
        ) {
            Text(
                text = title,
                color = if (enabled) palette.ink else palette.secondaryInk.copy(alpha = 0.6f),
                fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold,
            )
            Text(
                text = subtitle,
                color = palette.secondaryInk,
                fontSize = 12.5.sp,
            )
        }
        Spacer(Modifier.size(0.dp))
    }
}

private fun rateLabel(rate: Float): String =
    if (rate == rate.toInt().toFloat()) "${rate.toInt()}x" else "${rate}x"

private fun formatRemaining(ms: Long): String {
    val total = (ms / 1000).coerceAtLeast(0)
    return "%d:%02d 后暂停".format(total / 60, total % 60)
}
