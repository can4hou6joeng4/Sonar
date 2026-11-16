@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class, androidx.compose.foundation.layout.ExperimentalLayoutApi::class)

package cn.bobochang.sonar.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.FilterList
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cn.bobochang.sonar.data.library.AddedPeriod
import cn.bobochang.sonar.data.library.PlaylistEntry
import cn.bobochang.sonar.data.library.PlaylistFilter
import cn.bobochang.sonar.data.library.PlaylistOrder
import cn.bobochang.sonar.data.library.playlistArtists
import cn.bobochang.sonar.ui.theme.LocalSonarPalette

@Composable
fun PlaylistFilterButton(
    entries: List<PlaylistEntry>,
    filter: PlaylistFilter,
    onChange: (PlaylistFilter) -> Unit,
    hasDates: Boolean = true,
) {
    val palette = LocalSonarPalette.current
    var open by remember { mutableStateOf(false) }
    var query by remember { mutableStateOf("") }
    val artists = remember(entries) { playlistArtists(entries) }
    Box {
        IconButton(onClick = { open = true; query = "" }) {
            Icon(Icons.Rounded.FilterList, contentDescription = if (filter.isActive) "筛选与排序，条件已生效" else "筛选与排序",
                tint = if (filter.isActive) palette.accent else palette.ink)
        }
        if (filter.isActive) Box(Modifier.align(Alignment.TopEnd).padding(6.dp).size(7.dp).background(palette.accent, CircleShape))
    }
    if (open) {
        ModalBottomSheet(onDismissRequest = { open = false }, containerColor = palette.background) {
            Column(Modifier.fillMaxWidth().heightIn(max = 640.dp).verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp).padding(bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text("筛选与排序", Modifier.weight(1f), color = palette.ink, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                    TextButton(onClick = { onChange(PlaylistFilter()); query = "" }) { Text("重置", color = palette.accent) }
                    TextButton(onClick = { open = false }) { Text("完成", color = palette.ink) }
                }
                Text("歌手", color = palette.secondaryInk, fontWeight = FontWeight.SemiBold)
                if (artists.size > 8) {
                    OutlinedTextField(value = query, onValueChange = { query = it }, singleLine = true,
                        label = { Text("搜索歌手") }, modifier = Modifier.fillMaxWidth())
                }
                ArtistOption("全部歌手", filter.artist == null) { onChange(filter.copy(artist = null)) }
                if (artists.isNotEmpty()) {
                    LazyColumn(Modifier.fillMaxWidth().heightIn(max = 190.dp)) {
                        items(artists.filter { it.contains(query.trim(), ignoreCase = true) }, key = { it }) { artist ->
                            ArtistOption(artist, filter.artist == artist) { onChange(filter.copy(artist = artist)) }
                        }
                    }
                    if (artists.none { it.contains(query.trim(), ignoreCase = true) }) {
                        Text("没有匹配的歌手", color = palette.secondaryInk, fontSize = 13.sp)
                    }
                }
                Text("添加时间", color = palette.secondaryInk, fontWeight = FontWeight.SemiBold)
                if (hasDates) {
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        AddedPeriod.entries.forEach { period ->
                            FilterChip(selected = filter.period == period, onClick = { onChange(filter.copy(period = period)) },
                                label = { Text(period.label) })
                        }
                    }
                } else {
                    Text("远程预览未提供成员添加时间", color = palette.secondaryInk, fontSize = 13.sp)
                }
                Text("排序", color = palette.secondaryInk, fontWeight = FontWeight.SemiBold)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    PlaylistOrder.entries.filter { hasDates || !it.needsDate }.forEach { order ->
                        FilterChip(selected = filter.order == order, onClick = { onChange(filter.copy(order = order)) },
                            label = { Text(order.label) })
                    }
                }
            }
        }
    }
}

@Composable
private fun ArtistOption(label: String, selected: Boolean, onClick: () -> Unit) {
    val palette = LocalSonarPalette.current
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f), color = if (selected) palette.accent else palette.ink, fontSize = 15.sp)
        if (selected) Icon(Icons.Rounded.Check, contentDescription = "已选中", tint = palette.accent, modifier = Modifier.size(18.dp))
    }
}

@Composable
fun PlaylistFilterSummary(filter: PlaylistFilter, count: Int, total: Int, onReset: () -> Unit) {
    if (!filter.isActive) return
    val palette = LocalSonarPalette.current
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
        val description = listOfNotNull(filter.artist, filter.period.takeIf { it != AddedPeriod.ALL }?.label,
            filter.order.takeIf { it != PlaylistOrder.ORIGINAL }?.label).joinToString(" · ")
        Text("$description · 显示 $count / $total 首", Modifier.weight(1f), color = palette.secondaryInk, fontSize = 12.sp)
        TextButton(onClick = onReset) { Text("重置", color = palette.accent) }
    }
}

@Composable
fun FilteredPlaylistEmpty(onReset: () -> Unit) {
    val palette = LocalSonarPalette.current
    Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 48.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text("没有符合条件的歌曲", color = palette.ink, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
        Text("调整筛选条件即可查看歌单中的其他歌曲", color = palette.secondaryInk, fontSize = 13.sp,
            modifier = Modifier.padding(top = 8.dp))
        TextButton(onClick = onReset) { Text("重置筛选与排序", color = palette.accent) }
    }
}
