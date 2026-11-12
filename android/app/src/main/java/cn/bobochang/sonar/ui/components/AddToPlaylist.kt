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
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.LibraryMusic
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cn.bobochang.sonar.data.library.UserPlaylist
import cn.bobochang.sonar.ui.theme.LocalSonarPalette
import cn.bobochang.sonar.ui.theme.cellHighlight

/** 收藏 / 歌单选择面板，沿用 iOS 弹层的排版。 */
@Composable
fun PlaylistPickerSheet(
    playlists: List<UserPlaylist>,
    isFavorite: Boolean,
    onToggleFavorite: () -> Unit,
    onPickPlaylist: (UserPlaylist) -> Unit,
    onCancel: () -> Unit,
) {
    val palette = LocalSonarPalette.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(palette.background)
            .padding(bottom = 16.dp),
    ) {
        SheetHeader(title = "收藏到歌单")
        LazyColumn(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(max = 420.dp)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            item {
                PickRow(
                    title = if (isFavorite) "已在「我的收藏」中" else "我的收藏",
                    subtitle = if (isFavorite) "再次点按取消收藏" else "保存到个人收藏",
                    icon = Icons.Rounded.Favorite,
                    selected = isFavorite,
                    onClick = onToggleFavorite,
                )
            }
            items(playlists, key = { it.id }) { playlist ->
                PickRow(
                    title = playlist.name,
                    subtitle = if (playlist.system) "系统歌单" else "个人歌单",
                    icon = Icons.Rounded.LibraryMusic,
                    selected = false,
                    onClick = { onPickPlaylist(playlist) },
                )
            }
        }
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp)
                .padding(top = 8.dp)
                .height(50.dp)
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

@Composable
private fun PickRow(
    title: String,
    subtitle: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    selected: Boolean,
    onClick: () -> Unit,
) {
    val palette = LocalSonarPalette.current
    val interaction = remember { MutableInteractionSource() }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .cellHighlight(interaction)
            .combinedClickable(interactionSource = interaction, indication = null, onClick = onClick)
            .padding(horizontal = 8.dp)
            .heightIn(min = 58.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            modifier = Modifier
                .size(36.dp)
                .background(palette.accentContainer, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(icon, contentDescription = null, tint = palette.onAccentContainer, modifier = Modifier.size(18.dp))
        }
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, color = palette.ink, fontSize = 15.sp, fontWeight = FontWeight.Medium)
            Text(subtitle, color = palette.secondaryInk, fontSize = 12.sp)
        }
        if (selected) {
            Icon(Icons.Rounded.Check, contentDescription = null, tint = palette.accent, modifier = Modifier.size(20.dp))
        }
    }
}
