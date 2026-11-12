package cn.bobochang.sonar.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.History
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.SearchOff
import androidx.compose.material3.AssistChip
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import cn.bobochang.sonar.data.model.AlbumSummary
import cn.bobochang.sonar.data.model.ArtistSummary
import cn.bobochang.sonar.data.model.PlaylistSummary
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.di.AppContainer
import cn.bobochang.sonar.ui.components.Artwork
import cn.bobochang.sonar.ui.components.EmptyState
import cn.bobochang.sonar.ui.components.SongRow
import cn.bobochang.sonar.ui.theme.LocalSonarPalette
import cn.bobochang.sonar.ui.viewmodel.SearchMode
import cn.bobochang.sonar.ui.viewmodel.SearchUiState
import cn.bobochang.sonar.ui.viewmodel.SearchViewModel

@Composable
fun SearchScreen(
    container: AppContainer,
    snackbarHostState: SnackbarHostState,
    onOpenPlayer: () -> Unit,
    onOpenArtist: (String) -> Unit,
    onOpenAlbum: (String) -> Unit,
    onOpenPlaylist: (String) -> Unit,
) {
    val vm: SearchViewModel = viewModel(
        factory = viewModelFactory { initializer { SearchViewModel(container) } },
    )
    val state by vm.state.collectAsStateWithLifecycle()
    val favoriteIds by vm.favoriteIds.collectAsStateWithLifecycle()
    val palette = LocalSonarPalette.current
    val keyboard = LocalSoftwareKeyboardController.current
    val focusRequester = remember { FocusRequester() }

    LaunchedEffect(Unit) {
        vm.messages.collect { message -> snackbarHostState.showSnackbar(message) }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.background)
            .imePadding(),
    ) {
        OutlinedTextField(
            value = state.query,
            onValueChange = vm::onQueryChange,
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp)
                .focusRequester(focusRequester),
            placeholder = { Text("搜索歌曲、歌手、专辑或歌单") },
            leadingIcon = { Icon(Icons.Rounded.Search, contentDescription = null) },
            trailingIcon = {
                if (state.query.isNotEmpty()) {
                    IconButton(onClick = { vm.onQueryChange("") }) {
                        Icon(Icons.Rounded.Close, contentDescription = "清除")
                    }
                }
            },
            singleLine = true,
            shape = RoundedCornerShape(14.dp),
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            keyboardActions = KeyboardActions(
                onSearch = {
                    vm.submit()
                    keyboard?.hide()
                },
            ),
            colors = OutlinedTextFieldDefaults.colors(
                focusedContainerColor = palette.card,
                unfocusedContainerColor = palette.card,
                focusedBorderColor = palette.accent,
                unfocusedBorderColor = palette.divider,
                cursorColor = palette.accent,
            ),
        )

        LazyRow(
            contentPadding = PaddingValues(horizontal = 16.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(SearchMode.entries) { mode ->
                FilterChip(
                    selected = state.mode == mode,
                    onClick = { vm.setMode(mode) },
                    label = { Text(mode.label) },
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = palette.accent.copy(alpha = 0.16f),
                        selectedLabelColor = palette.accent,
                        labelColor = palette.secondaryInk,
                    ),
                )
            }
        }

        Box(modifier = Modifier.weight(1f)) {
            when {
                state.query.isBlank() -> SearchLanding(
                    state = state,
                    onUseSuggestion = vm::useSuggestion,
                    onRemoveHistory = vm::removeHistory,
                    onClearHistory = vm::clearHistory,
                )

                state.loading && stateEmpty(state) -> {
                    CircularProgressIndicator(
                        modifier = Modifier.align(Alignment.Center),
                        color = palette.accent,
                    )
                }

                state.error != null -> {
                    EmptyState(
                        icon = Icons.Rounded.SearchOff,
                        title = "搜索失败",
                        subtitle = state.error.orEmpty(),
                        actionLabel = "重试",
                        onAction = vm::submit,
                    )
                }

                stateEmpty(state) -> {
                    EmptyState(
                        icon = Icons.Rounded.SearchOff,
                        title = "没有找到结果",
                        subtitle = "换一个关键词，或切换搜索类型再试。",
                    )
                }

                else -> {
                    SearchResults(
                        state = state,
                        favoriteIds = favoriteIds,
                        onPlay = { index -> vm.play(index) },
                        onFavorite = vm::toggleFavorite,
                        onPlayNext = vm::playNext,
                        onEnqueue = vm::enqueue,
                        onLoadMore = vm::loadMore,
                        onOpenArtist = onOpenArtist,
                        onOpenAlbum = onOpenAlbum,
                        onOpenPlaylist = onOpenPlaylist,
                    )
                }
            }
        }
    }
}

@Composable
private fun SearchLanding(
    state: SearchUiState,
    onUseSuggestion: (String) -> Unit,
    onRemoveHistory: (String) -> Unit,
    onClearHistory: () -> Unit,
) {
    val palette = LocalSonarPalette.current
    LazyColumn(contentPadding = PaddingValues(bottom = 24.dp)) {
        if (state.hot.isNotEmpty()) {
            item {
                Text(
                    text = "热门搜索",
                    style = MaterialTheme.typography.titleMedium,
                    color = palette.ink,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp),
                )
            }
            item {
                LazyRow(
                    contentPadding = PaddingValues(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    items(state.hot) { keyword ->
                        AssistChip(
                            onClick = { onUseSuggestion(keyword) },
                            label = { Text(keyword) },
                        )
                    }
                }
            }
        }
        if (state.history.isNotEmpty()) {
            item {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(start = 16.dp, end = 8.dp, top = 16.dp, bottom = 4.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = "最近搜索",
                        style = MaterialTheme.typography.titleMedium,
                        color = palette.ink,
                        modifier = Modifier.weight(1f),
                    )
                    TextButton(onClick = onClearHistory) { Text("清空") }
                }
            }
            items(state.history) { keyword ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onUseSuggestion(keyword) }
                        .padding(horizontal = 16.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        Icons.Rounded.History,
                        contentDescription = null,
                        tint = palette.secondaryInk,
                        modifier = Modifier.size(18.dp),
                    )
                    Spacer(Modifier.width(12.dp))
                    Text(
                        text = keyword,
                        style = MaterialTheme.typography.bodyMedium,
                        color = palette.ink,
                        modifier = Modifier.weight(1f),
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    IconButton(onClick = { onRemoveHistory(keyword) }) {
                        Icon(
                            Icons.Rounded.Close,
                            contentDescription = "删除",
                            tint = palette.secondaryInk,
                            modifier = Modifier.size(16.dp),
                        )
                    }
                }
            }
        }
        if (state.hot.isEmpty() && state.history.isEmpty()) {
            item {
                EmptyState(
                    icon = Icons.Rounded.Search,
                    title = "搜索网易云音乐",
                    subtitle = "支持歌曲、歌手、专辑与歌单。在线功能需要网络。",
                )
            }
        }
    }
}

@Composable
private fun SearchResults(
    state: SearchUiState,
    favoriteIds: Set<String>,
    onPlay: (Int) -> Unit,
    onFavorite: (Track) -> Unit,
    onPlayNext: (Track) -> Unit,
    onEnqueue: (Track) -> Unit,
    onLoadMore: () -> Unit,
    onOpenArtist: (String) -> Unit,
    onOpenAlbum: (String) -> Unit,
    onOpenPlaylist: (String) -> Unit,
) {
    LazyColumn(contentPadding = PaddingValues(bottom = 24.dp)) {
        when (state.mode) {
            SearchMode.SONGS -> itemsIndexed(state.songs, key = { _, track -> track.musicId }) { index, track ->
                SongRow(
                    track = track,
                    isFavorite = track.musicId in favoriteIds,
                    onClick = { onPlay(index) },
                    onFavorite = { onFavorite(track) },
                    onPlayNext = { onPlayNext(track) },
                    onEnqueue = { onEnqueue(track) },
                )
            }

            SearchMode.ARTISTS -> items(state.artists, key = { it.stableId }) { artist ->
                ArtistRow(artist = artist, onClick = { onOpenArtist(artist.id) })
            }

            SearchMode.ALBUMS -> items(state.albums, key = { it.stableId }) { album ->
                AlbumRow(album = album, onClick = { onOpenAlbum(album.id) })
            }

            SearchMode.PLAYLISTS -> items(state.playlists, key = { it.key }) { playlist ->
                PlaylistRow(playlist = playlist, onClick = { onOpenPlaylist(playlist.id) })
            }
        }
        if (state.hasMore) {
            item {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    TextButton(onClick = onLoadMore, enabled = !state.loading) {
                        Text(if (state.loading) "加载中…" else "加载更多")
                    }
                }
            }
        }
    }
}

@Composable
private fun ArtistRow(artist: ArtistSummary, onClick: () -> Unit) {
    val palette = LocalSonarPalette.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Artwork(url = artist.imageUrl, size = 52.dp, corner = 26.dp)
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(artist.name, style = MaterialTheme.typography.titleMedium, color = palette.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            val detail = listOfNotNull(
                artist.songCount?.let { "$it 首歌曲" },
                artist.albumCount?.let { "$it 张专辑" },
            ).joinToString(" · ")
            if (detail.isNotBlank()) {
                Text(detail, style = MaterialTheme.typography.bodySmall, color = palette.secondaryInk)
            }
        }
    }
}

@Composable
private fun AlbumRow(album: AlbumSummary, onClick: () -> Unit) {
    val palette = LocalSonarPalette.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Artwork(url = album.imageUrl, size = 52.dp, corner = 10.dp)
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(album.name, style = MaterialTheme.typography.titleMedium, color = palette.ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(
                text = listOf(album.artist, album.releaseDate ?: "").filter { it.isNotBlank() }.joinToString(" · "),
                style = MaterialTheme.typography.bodySmall,
                color = palette.secondaryInk,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

@Composable
private fun PlaylistRow(playlist: PlaylistSummary, onClick: () -> Unit) {
    val palette = LocalSonarPalette.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Artwork(url = playlist.imageUrl, size = 52.dp, corner = 10.dp)
        Spacer(Modifier.width(12.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(playlist.name, style = MaterialTheme.typography.titleMedium, color = palette.ink, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Text(
                text = listOf(playlist.author, playlist.total?.let { "$it 首" } ?: "").filter { it.isNotBlank() }.joinToString(" · "),
                style = MaterialTheme.typography.bodySmall,
                color = palette.secondaryInk,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

private fun stateEmpty(state: SearchUiState): Boolean = when (state.mode) {
    SearchMode.SONGS -> state.songs.isEmpty()
    SearchMode.ARTISTS -> state.artists.isEmpty()
    SearchMode.ALBUMS -> state.albums.isEmpty()
    SearchMode.PLAYLISTS -> state.playlists.isEmpty()
}
