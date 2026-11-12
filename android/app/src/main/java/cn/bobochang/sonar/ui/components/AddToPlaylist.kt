package cn.bobochang.sonar.ui.components

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Add
import androidx.compose.material.icons.rounded.LibraryMusic
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import cn.bobochang.sonar.data.library.UserPlaylist
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.di.AppContainer
import cn.bobochang.sonar.ui.theme.LocalSonarPalette
import kotlinx.coroutines.launch

val LocalAddToPlaylist = staticCompositionLocalOf<((Track) -> Unit)?> { null }

/**
 * 全局的“添加到歌单”对话框。SongRow 通过 CompositionLocal 触发，
 * 避免所有列表页重复传递歌单数据与回调。
 */
@Composable
fun AddToPlaylistHost(
    container: AppContainer,
    snackbarHostState: SnackbarHostState,
    content: @Composable () -> Unit,
) {
    var target by remember { mutableStateOf<Track?>(null) }
    var creating by remember { mutableStateOf(false) }
    var newName by remember { mutableStateOf("") }
    val playlists by remember {
        container.library.observePlaylists()
    }.collectAsStateWithLifecycle(initialValue = emptyList())
    val scope = rememberCoroutineScope()
    val palette = LocalSonarPalette.current

    val open: (Track) -> Unit = remember {
        {
            target = it
            creating = false
            newName = ""
        }
    }

    CompositionLocalProvider(LocalAddToPlaylist provides open) {
        content()
    }

    target?.let { track ->
        if (creating) {
            AlertDialog(
                onDismissRequest = { creating = false },
                title = { Text("新建歌单") },
                text = {
                    OutlinedTextField(
                        value = newName,
                        onValueChange = { newName = it.take(200) },
                        singleLine = true,
                        label = { Text("歌单名称") },
                    )
                },
                confirmButton = {
                    Button(
                        onClick = {
                            val name = newName.trim().ifEmpty { "新建歌单" }
                            val current = track
                            target = null
                            creating = false
                            scope.launch {
                                runCatching {
                                    val id = container.library.createPlaylist(name)
                                    container.library.addTracksToPlaylist(id, listOf(current))
                                }.onSuccess {
                                    snackbarHostState.showSnackbar("已添加到「$name」")
                                }.onFailure { error ->
                                    snackbarHostState.showSnackbar(error.message ?: "添加失败")
                                }
                            }
                        },
                    ) { Text("创建并添加") }
                },
                dismissButton = {
                    TextButton(onClick = { creating = false }) { Text("取消") }
                },
            )
        } else {
            AlertDialog(
                onDismissRequest = { target = null },
                title = { Text("添加到歌单") },
                text = {
                    Column {
                        Text(
                            text = "${track.title} · ${track.artist}",
                            style = MaterialTheme.typography.bodySmall,
                            color = palette.secondaryInk,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                        Spacer(Modifier.height(12.dp))
                        if (playlists.isEmpty()) {
                            Text(
                                "还没有个人歌单。新建一个歌单来收藏这首歌。",
                                style = MaterialTheme.typography.bodySmall,
                                color = palette.secondaryInk,
                            )
                        } else {
                            LazyColumn(modifier = Modifier.heightIn(max = 320.dp)) {
                                items(playlists, key = { it.id }) { playlist ->
                                    PlaylistPickRow(
                                        playlist = playlist,
                                        onPick = {
                                            target = null
                                            scope.launch {
                                                runCatching {
                                                    container.library.addTracksToPlaylist(
                                                        playlist.id,
                                                        listOf(track),
                                                    )
                                                }.onSuccess { count ->
                                                    snackbarHostState.showSnackbar(
                                                        if (count > 0) {
                                                            "已添加到「${playlist.name}」"
                                                        } else {
                                                            "歌曲已在「${playlist.name}」中"
                                                        },
                                                    )
                                                }.onFailure { error ->
                                                    snackbarHostState.showSnackbar(error.message ?: "添加失败")
                                                }
                                            }
                                        },
                                    )
                                }
                            }
                        }
                    }
                },
                confirmButton = {
                    TextButton(onClick = { creating = true }) {
                        Icon(Icons.Rounded.Add, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.width(4.dp))
                        Text("新建歌单")
                    }
                },
                dismissButton = {
                    TextButton(onClick = { target = null }) { Text("取消") }
                },
            )
        }
    }
}

@Composable
private fun PlaylistPickRow(playlist: UserPlaylist, onPick: () -> Unit) {
    val palette = LocalSonarPalette.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onPick)
            .padding(vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(
            imageVector = Icons.Rounded.LibraryMusic,
            contentDescription = null,
            tint = palette.accent,
            modifier = Modifier.size(20.dp),
        )
        Text(
            text = playlist.name,
            style = MaterialTheme.typography.bodyMedium,
            color = palette.ink,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.weight(1f),
        )
    }
}
