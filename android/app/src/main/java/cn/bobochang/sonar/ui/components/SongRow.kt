@file:OptIn(
    androidx.compose.foundation.ExperimentalFoundationApi::class,
)

package cn.bobochang.sonar.ui.components

import android.view.HapticFeedbackConstants
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.data.model.highestKnownQuality
import cn.bobochang.sonar.ui.theme.LocalSonarPalette
import cn.bobochang.sonar.ui.theme.SonarBaseTextStyle
import cn.bobochang.sonar.ui.theme.cellHighlight
import cn.bobochang.sonar.ui.theme.withTnum

sealed interface SongLeading {
    data object Cover : SongLeading
    data class Index(val value: Int) : SongLeading
}

sealed interface SongTrailing {
    data object Play : SongTrailing
    data object More : SongTrailing
    data class CollectionStatus(val isCollected: Boolean) : SongTrailing
}

/** 对应 iOS `SongRow`。 */
@Composable
fun SongRow(
    track: Track,
    modifier: Modifier = Modifier,
    leading: SongLeading = SongLeading.Cover,
    trailing: SongTrailing = SongTrailing.More,
    showAlbum: Boolean = true,
    showDivider: Boolean = true,
    isCurrent: Boolean = false,
    isSelected: Boolean = false,
    isPlaying: Boolean = false,
    onPlay: (() -> Unit)? = null,
    onAction: (() -> Unit)? = null,
) {
    val palette = LocalSonarPalette.current
    val isUnavailable = !track.source.isEnabled || !track.isPlayable
    val interaction = remember { MutableInteractionSource() }
    val view = LocalView.current

    val primary = when {
        isUnavailable -> palette.secondaryInk
        isSelected -> palette.onAccentContainer
        isCurrent -> palette.accent
        else -> palette.ink
    }
    val secondary = when {
        isUnavailable -> palette.secondaryInk.copy(alpha = 0.72f)
        isSelected -> palette.onAccentContainer.copy(alpha = 0.86f)
        isCurrent -> palette.accent.copy(alpha = 0.86f)
        else -> palette.secondaryInk
    }
    val background = when {
        isSelected -> palette.accentContainer.copy(alpha = 0.56f)
        isCurrent -> palette.accentContainer.copy(alpha = 0.12f)
        else -> androidx.compose.ui.graphics.Color.Transparent
    }

    val dividerInset = when (leading) {
        SongLeading.Cover -> 70.dp
        is SongLeading.Index -> 52.dp
    }

    Box(modifier = modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 2.dp)
                .cellHighlight(interaction)
                .background(background, RoundedCornerShape(10.dp))
                .clip(RoundedCornerShape(10.dp))
                .combinedClickable(
                    enabled = true,
                    interactionSource = interaction,
                    indication = null,
                    onClick = {
                        if (onPlay != null && !isUnavailable) onPlay()
                        else if (onAction != null) onAction()
                    },
                    onLongClick = {
                        if (onAction != null) {
                            view.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
                            onAction()
                        }
                    },
                )
                .padding(horizontal = 16.dp)
                .defaultMinSize(minHeight = 60.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Row(
                modifier = Modifier.weight(1f),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                when (leading) {
                    SongLeading.Cover -> {
                        Box {
                            PlayerArtwork(track = track, size = 44.dp, cornerRadius = 7.dp)
                        }
                    }

                    is SongLeading.Index -> Box(
                        Modifier
                            .width(26.dp)
                            .height(44.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        if (isCurrent) {
                            PlayingEqualizer(isAnimating = isPlaying, color = palette.accent)
                        } else {
                            Text(
                                text = "${leading.value}",
                                color = palette.tertiaryInk,
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Normal,
                                style = SonarBaseTextStyle.withTnum(),
                            )
                        }
                    }
                }

                Column(
                    modifier = Modifier
                        .weight(1f)
                        .padding(vertical = 4.dp),
                    verticalArrangement = Arrangement.spacedBy(3.dp),
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        if (isCurrent && leading == SongLeading.Cover) {
                            PlayingEqualizer(isAnimating = isPlaying, color = primary)
                        }
                        Text(
                            text = track.title,
                            color = primary,
                            fontSize = 15.sp,
                            fontWeight = FontWeight.Medium,
                            letterSpacing = (-0.1).sp,
                            style = SonarBaseTextStyle,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(5.dp),
                    ) {
                        if (!track.source.isEnabled) {
                            Text(
                                text = "不可用",
                                color = palette.secondaryInk,
                                fontSize = 11.sp,
                                style = SonarBaseTextStyle,
                            )
                        } else if (!track.isPlayable) {
                            Text(
                                text = "已下架",
                                color = palette.secondaryInk,
                                fontSize = 11.sp,
                                style = SonarBaseTextStyle,
                            )
                        } else {
                            QualityBadge(track.highestKnownQuality)
                        }
                        Text(
                            text = subtitle(track, showAlbum),
                            color = secondary,
                            fontSize = 12.sp,
                            fontWeight = FontWeight.Normal,
                            style = SonarBaseTextStyle,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
            }

            when (trailing) {
                SongTrailing.Play -> {
                    if (onPlay != null) {
                        CircleGlyphButton(
                            icon = Icons.Rounded.PlayArrow,
                            size = 19.dp,
                            tint = if (isUnavailable) palette.tertiaryInk else palette.ink,
                            onClick = { if (!isUnavailable) onPlay() },
                            enabled = !isUnavailable,
                        )
                    }
                }

                SongTrailing.More -> {
                    if (onAction != null) {
                        CircleGlyphButton(
                            icon = Icons.Rounded.MoreHoriz,
                            size = 18.dp,
                            tint = palette.secondaryInk,
                            onClick = onAction,
                        )
                    } else {
                        Spacer(Modifier.size(44.dp))
                    }
                }

                is SongTrailing.CollectionStatus -> {
                    if (trailing.isCollected) {
                        Icon(
                            imageVector = Icons.Rounded.Check,
                            contentDescription = "已收藏，导入时跳过",
                            tint = palette.secondaryInk,
                            modifier = Modifier.size(44.dp).padding(14.dp),
                        )
                    } else {
                        Spacer(Modifier.size(44.dp))
                    }
                }
            }
        }

        if (showDivider) {
            HorizontalDivider(
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(start = dividerInset),
                thickness = 0.5.dp,
                color = palette.divider,
            )
        }
    }
}

@Composable
private fun CircleGlyphButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    size: androidx.compose.ui.unit.Dp,
    tint: androidx.compose.ui.graphics.Color,
    onClick: () -> Unit,
    enabled: Boolean = true,
) {
    val interaction = remember { MutableInteractionSource() }
    Box(
        modifier = Modifier
            .size(44.dp)
            .clip(CircleShape)
            .combinedClickable(
                interactionSource = interaction,
                indication = null,
                onClick = onClick,
                enabled = enabled,
            ),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(size))
    }
}

private fun subtitle(track: Track, showAlbum: Boolean): String {
    val album = track.album.trim()
    val values = if (showAlbum && album.isNotEmpty() && album != track.title) {
        listOf(track.artist, album)
    } else {
        listOf(track.artist)
    }
    val displayed = if (track.source.isEnabled) values else listOf(track.source.displayName) + values
    return displayed.filter { it.isNotBlank() }.joinToString(" · ")
}
