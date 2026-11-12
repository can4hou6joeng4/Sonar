package cn.bobochang.sonar.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import cn.bobochang.sonar.data.model.AlbumSummary
import cn.bobochang.sonar.data.model.ArtistSummary
import cn.bobochang.sonar.data.model.PlaylistSummary
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.di.AppContainer
import cn.bobochang.sonar.playback.PlayerUiState
import cn.bobochang.sonar.ui.components.RemoteArtwork
import cn.bobochang.sonar.ui.components.SkeletonSongList
import cn.bobochang.sonar.ui.components.SongRow
import cn.bobochang.sonar.ui.components.SongTrailing
import cn.bobochang.sonar.ui.theme.cellHighlight
import cn.bobochang.sonar.ui.theme.LocalSonarPalette
import cn.bobochang.sonar.ui.viewmodel.SearchMode
import cn.bobochang.sonar.ui.viewmodel.SearchUiState
import cn.bobochang.sonar.ui.viewmodel.SearchViewModel
import kotlinx.coroutines.delay

/** 对应 iOS `HomeSearchOverlay`：浮在当前页上的搜索面板。 */
@Composable
fun SearchOverlay(
    container: AppContainer,
    playerState: PlayerUiState,
    onClose: () -> Unit,
    onOpenArtist: (ArtistSummary) -> Unit,
    onOpenAlbum: (AlbumSummary) -> Unit,
    onOpenPlaylist: (PlaylistSummary) -> Unit,
    onSongAction: (Track) -> Unit,
) {
    val vm: SearchViewModel = viewModel(
        factory = viewModelFactory { initializer { SearchViewModel(container) } },
    )
    val state by vm.state.collectAsStateWithLifecycle()
    val palette = LocalSonarPalette.current
    val keyboard = LocalSoftwareKeyboardController.current
    val focusRequester = remember { FocusRequester() }
    fun close() {
        keyboard?.hide()
        vm.onQueryChange("")
        onClose()
    }

    fun runSearch(keyword: String) {
        if (keyword.isBlank()) return
        keyboard?.hide()
        vm.useSuggestion(keyword)
    }

    LaunchedEffect(Unit) {
        delay(80)
        focusRequester.requestFocus()
        keyboard?.show()
    }

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val cardMaxHeight = minOf(maxHeight - 84.dp, 600.dp).coerceAtLeast(0.dp)
        val landingMaxHeight = minOf(maxHeight - 84.dp, 520.dp).coerceAtLeast(0.dp)

        Box(
            Modifier
                .fillMaxSize()
                .background(Color.Black.copy(alpha = 0.38f))
                .clickable(
                    interactionSource = remember { MutableInteractionSource() },
                    indication = null,
                    onClick = ::close,
                ),
        )

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .statusBarsPadding()
                .imePadding()
                .padding(top = 6.dp, bottom = 16.dp)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            SearchBar(
                query = state.query,
                onQueryChange = vm::onQueryChange,
                onSubmit = {
                    keyboard?.hide()
                    vm.submit()
                },
                onClear = { vm.onQueryChange("") },
                onCancel = ::close,
                focusRequester = focusRequester,
            )

            if (state.query.isBlank()) {
                SearchLanding(
                    state = state,
                    maxHeight = landingMaxHeight,
                    onRun = ::runSearch,
                    onClearHistory = vm::clearHistory,
                )
            } else {
                SearchResultsCard(
                    state = state,
                    playerState = playerState,
                    maxHeight = cardMaxHeight,
                    onModeChange = { mode ->
                        keyboard?.hide()
                        vm.setMode(mode)
                    },
                    onPlay = { index -> vm.play(index) },
                    onAction = { track ->
                        keyboard?.hide()
                        onSongAction(track)
                    },
                    onLoadMore = vm::loadMore,
                    onRetry = vm::submit,
                    onOpenArtist = { artist ->
                        keyboard?.hide()
                        vm.onQueryChange("")
                        onOpenArtist(artist)
                    },
                    onOpenAlbum = { album ->
                        keyboard?.hide()
                        vm.onQueryChange("")
                        onOpenAlbum(album)
                    },
                    onOpenPlaylist = { playlist ->
                        keyboard?.hide()
                        vm.onQueryChange("")
                        onOpenPlaylist(playlist)
                    },
                )
            }
        }
    }
}

@Composable
private fun SearchBar(
    query: String,
    onQueryChange: (String) -> Unit,
    onSubmit: () -> Unit,
    onClear: () -> Unit,
    onCancel: () -> Unit,
    focusRequester: FocusRequester,
) {
    val palette = LocalSonarPalette.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .shadow(16.dp, CircleShape)
            .background(palette.background, CircleShape)
            .border(0.5.dp, palette.divider, CircleShape)
            .padding(end = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            modifier = Modifier
                .weight(1f)
                .heightIn(min = 52.dp)
                .padding(start = 16.dp, end = if (query.isEmpty()) 12.dp else 0.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(
                imageVector = Icons.Rounded.Search,
                contentDescription = null,
                tint = palette.secondaryInk,
                modifier = Modifier.size(16.dp),
            )
            Box(Modifier.weight(1f)) {
                if (query.isEmpty()) {
                    Text(
                        text = "搜索歌曲或歌手",
                        color = palette.secondaryInk,
                        fontSize = 16.sp,
                    )
                }
                BasicTextField(
                    value = query,
                    onValueChange = onQueryChange,
                    modifier = Modifier
                        .fillMaxWidth()
                        .focusRequester(focusRequester),
                    singleLine = true,
                    textStyle = TextStyle(
                        color = palette.ink,
                        fontSize = 16.sp,
                    ),
                    cursorBrush = SolidColor(palette.accent),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
                    keyboardActions = KeyboardActions(onSearch = { onSubmit() }),
                )
            }
            if (query.isNotEmpty()) {
                Box(
                    modifier = Modifier
                        .size(44.dp)
                        .clickable(onClick = onClear),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        imageVector = Icons.Rounded.Close,
                        contentDescription = "清空",
                        tint = palette.secondaryInk,
                        modifier = Modifier.size(17.dp),
                    )
                }
            }
        }
        Box(
            modifier = Modifier
                .size(44.dp)
                .clickable(onClick = onCancel),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = Icons.Rounded.Close,
                contentDescription = "取消搜索",
                tint = palette.secondaryInk,
                modifier = Modifier.size(14.dp),
            )
        }
    }
}

@Composable
private fun SearchLanding(
    state: SearchUiState,
    maxHeight: androidx.compose.ui.unit.Dp,
    onRun: (String) -> Unit,
    onClearHistory: () -> Unit,
) {
    val palette = LocalSonarPalette.current
    LazyColumn(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(max = maxHeight)
            .shadow(20.dp, RoundedCornerShape(22.dp))
            .background(palette.background, RoundedCornerShape(22.dp))
            .clip(RoundedCornerShape(22.dp))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = {},
            ),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(18.dp),
    ) {
        if (state.history.isNotEmpty()) {
            item(key = "history") {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            "搜索历史",
                            color = palette.ink,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Spacer(Modifier.weight(1f))
                        Text(
                            "清空",
                            color = palette.secondaryInk,
                            fontSize = 12.sp,
                            modifier = Modifier.clickable(onClick = onClearHistory),
                        )
                    }
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(state.history, key = { it }) { keyword ->
                            Box(
                                modifier = Modifier
                                    .height(32.dp)
                                    .background(palette.card, CircleShape)
                                    .clickable { onRun(keyword) }
                                    .padding(horizontal = 12.dp),
                                contentAlignment = Alignment.Center,
                            ) {
                                Text(keyword, color = palette.ink, fontSize = 13.sp)
                            }
                        }
                    }
                }
            }
        }
        item(key = "hot") {
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    "热门搜索",
                    color = palette.ink,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.SemiBold,
                )
                if (state.hot.isEmpty()) {
                    Box(
                        modifier = Modifier.fillMaxWidth().heightIn(min = 80.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text("暂无热门搜索", color = palette.tertiaryInk, fontSize = 13.sp)
                    }
                } else {
                    state.hot.take(10).forEachIndexed { index, keyword ->
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(40.dp)
                                .clickable { onRun(keyword) },
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(10.dp),
                        ) {
                            Text(
                                text = "${index + 1}",
                                color = if (index < 3) palette.accent else palette.secondaryInk,
                                fontSize = 14.sp,
                                fontWeight = FontWeight.SemiBold,
                                modifier = Modifier.width(18.dp),
                            )
                            Text(
                                text = keyword,
                                color = palette.ink,
                                fontSize = 15.sp,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun SearchResultsCard(
    state: SearchUiState,
    playerState: PlayerUiState,
    maxHeight: androidx.compose.ui.unit.Dp,
    onModeChange: (SearchMode) -> Unit,
    onPlay: (Int) -> Unit,
    onAction: (Track) -> Unit,
    onLoadMore: () -> Unit,
    onRetry: () -> Unit,
    onOpenArtist: (ArtistSummary) -> Unit,
    onOpenAlbum: (AlbumSummary) -> Unit,
    onOpenPlaylist: (PlaylistSummary) -> Unit,
) {
    val palette = LocalSonarPalette.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(max = maxHeight)
            .shadow(20.dp, RoundedCornerShape(22.dp))
            .background(palette.background, RoundedCornerShape(22.dp))
            .clip(RoundedCornerShape(22.dp))
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = {},
            ),
    ) {
        ScopePicker(selected = state.mode, onSelect = onModeChange)
        androidx.compose.material3.HorizontalDivider(color = palette.divider, thickness = 0.5.dp)
        when {
            state.loading && state.isEmpty() -> SkeletonSongList(rows = 6)
            state.error != null && state.isEmpty() -> Column(
                modifier = Modifier.fillMaxWidth().heightIn(min = 200.dp).padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Text("搜索不可用", color = palette.ink, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.height(6.dp))
                Text(state.error ?: "请稍后重试", color = palette.secondaryInk, fontSize = 13.sp)
                Spacer(Modifier.height(12.dp))
                Text(
                    "重试搜索",
                    color = palette.accent,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Medium,
                    modifier = Modifier.clickable(onClick = onRetry).padding(8.dp),
                )
            }
            state.isEmpty() -> Box(
                modifier = Modifier.fillMaxWidth().heightIn(min = 200.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    when (state.mode) {
                        SearchMode.SONGS -> "未找到歌曲"
                        SearchMode.ARTISTS -> "未找到歌手"
                        SearchMode.ALBUMS -> "未找到专辑"
                        SearchMode.PLAYLISTS -> "未找到歌单"
                    },
                    color = palette.secondaryInk,
                    fontSize = 14.sp,
                )
            }
            else -> LazyColumn(
                modifier = Modifier.fillMaxWidth(),
                contentPadding = PaddingValues(bottom = 8.dp),
            ) {
                when (state.mode) {
                    SearchMode.SONGS -> itemsIndexed(
                        state.songs,
                        key = { _, track -> track.musicId },
                    ) { index, track ->
                        SongRow(
                            track = track,
                            trailing = SongTrailing.More,
                            showDivider = index < state.songs.lastIndex,
                            isCurrent = playerState.track?.musicId == track.musicId,
                            isPlaying = playerState.isPlaying,
                            onPlay = { onPlay(index) },
                            onAction = { onAction(track) },
                        )
                    }

                    SearchMode.ARTISTS -> items(state.artists, key = { it.stableId }) { artist ->
                        SearchArtistRow(artist) { onOpenArtist(artist) }
                    }

                    SearchMode.ALBUMS -> items(state.albums, key = { it.stableId }) { album ->
                        SearchAlbumRow(album) { onOpenAlbum(album) }
                    }

                    SearchMode.PLAYLISTS -> items(state.playlists, key = { it.key }) { playlist ->
                        SearchPlaylistRow(playlist) { onOpenPlaylist(playlist) }
                    }
                }
                if (state.hasMore) {
                    item(key = "more") {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(48.dp)
                                .clickable(enabled = !state.loading, onClick = onLoadMore),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                if (state.loading) "正在加载…" else "加载更多",
                                color = palette.secondaryInk,
                                fontSize = 13.sp,
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun ScopePicker(selected: SearchMode, onSelect: (SearchMode) -> Unit) {
    val palette = LocalSonarPalette.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 6.dp)
            .background(palette.inputFill, CircleShape)
            .padding(3.dp),
    ) {
        SearchMode.entries.forEach { mode ->
            val active = selected == mode
            Box(
                modifier = Modifier
                    .weight(1f)
                    .height(38.dp)
                    .clip(CircleShape)
                    .background(if (active) palette.background else Color.Transparent)
                    .clickable { onSelect(mode) },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = mode.label,
                    color = palette.ink,
                    fontSize = 14.sp,
                    fontWeight = if (active) FontWeight.SemiBold else FontWeight.Normal,
                )
            }
        }
    }
}

@Composable
private fun SearchArtistRow(artist: ArtistSummary, onClick: () -> Unit) {
    val palette = LocalSonarPalette.current
    val interaction = remember { MutableInteractionSource() }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 68.dp)
            .cellHighlight(interaction)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick)
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        RemoteArtwork(url = artist.imageUrl, size = 56.dp, cornerRadius = 28.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(
                    artist.name,
                    color = palette.ink,
                    fontSize = 16.sp,
                    fontWeight = FontWeight.Bold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f, fill = false),
                )
                Text(
                    "歌手",
                    color = palette.accent,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier
                        .background(palette.accent.copy(alpha = 0.12f), CircleShape)
                        .padding(horizontal = 6.dp, vertical = 1.5.dp),
                )
            }
            Text(
                artistMetadata(artist),
                color = palette.secondaryInk,
                fontSize = 12.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Chevron()
    }
}

@Composable
private fun SearchAlbumRow(album: AlbumSummary, onClick: () -> Unit) {
    val palette = LocalSonarPalette.current
    val interaction = remember { MutableInteractionSource() }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 76.dp)
            .cellHighlight(interaction)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick)
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        RemoteArtwork(url = album.imageUrl, size = 56.dp, cornerRadius = 8.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                album.name,
                color = palette.ink,
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                albumMetadata(album),
                color = palette.secondaryInk,
                fontSize = 12.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Chevron()
    }
}

@Composable
private fun SearchPlaylistRow(playlist: PlaylistSummary, onClick: () -> Unit) {
    val palette = LocalSonarPalette.current
    val interaction = remember { MutableInteractionSource() }
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 76.dp)
            .cellHighlight(interaction)
            .clickable(interactionSource = interaction, indication = null, onClick = onClick)
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        RemoteArtwork(url = playlist.imageUrl, size = 56.dp, cornerRadius = 8.dp)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                playlist.name,
                color = palette.ink,
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                playlist.author.ifBlank { "网易云歌单" },
                color = palette.secondaryInk,
                fontSize = 12.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Chevron()
    }
}

@Composable
private fun Chevron() {
    val palette = LocalSonarPalette.current
    Icon(
        imageVector = Icons.Rounded.ChevronRight,
        contentDescription = null,
        tint = palette.outline,
        modifier = Modifier.size(16.dp),
    )
}

private fun artistMetadata(artist: ArtistSummary): String {
    val parts = buildList {
        artist.songCount?.takeIf { it > 0 }?.let { add("$it 首歌曲") }
        artist.albumCount?.takeIf { it > 0 }?.let { add("$it 张专辑") }
    }
    return parts.ifEmpty { listOf("歌手") }.joinToString(" · ")
}

private fun albumMetadata(album: AlbumSummary): String {
    val parts = buildList {
        if (album.artist.isNotBlank()) add(album.artist)
        album.trackCount?.takeIf { it > 0 }?.let { add("$it 首") }
        album.releaseDate?.takeIf { it.isNotBlank() }?.let { add(it) }
    }
    return parts.ifEmpty { listOf("专辑") }.joinToString(" · ")
}

private fun SearchUiState.isEmpty(): Boolean = when (mode) {
    SearchMode.SONGS -> songs.isEmpty()
    SearchMode.ARTISTS -> artists.isEmpty()
    SearchMode.ALBUMS -> albums.isEmpty()
    SearchMode.PLAYLISTS -> playlists.isEmpty()
}
