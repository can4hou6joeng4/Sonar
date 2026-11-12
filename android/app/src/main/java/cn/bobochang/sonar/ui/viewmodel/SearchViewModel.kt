package cn.bobochang.sonar.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import cn.bobochang.sonar.data.model.AlbumSummary
import cn.bobochang.sonar.data.model.ArtistSummary
import cn.bobochang.sonar.data.model.PlaylistSummary
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.data.net.SourceException
import cn.bobochang.sonar.di.AppContainer
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

enum class SearchMode(val label: String, val pageSize: Int) {
    SONGS("单曲", 25),
    ARTISTS("歌手", 20),
    ALBUMS("专辑", 20),
    PLAYLISTS("歌单", 20),
}

data class SearchUiState(
    val query: String = "",
    val mode: SearchMode = SearchMode.SONGS,
    val loading: Boolean = false,
    val songs: List<Track> = emptyList(),
    val artists: List<ArtistSummary> = emptyList(),
    val albums: List<AlbumSummary> = emptyList(),
    val playlists: List<PlaylistSummary> = emptyList(),
    val total: Int = 0,
    val page: Int = 1,
    val error: String? = null,
    val hot: List<String> = emptyList(),
    val history: List<String> = emptyList(),
) {
    val hasMore: Boolean
        get() = total > page * mode.pageSize
}

class SearchViewModel(private val container: AppContainer) : ViewModel() {
    private val _state = MutableStateFlow(SearchUiState())
    val state: StateFlow<SearchUiState> = _state.asStateFlow()

    private var searchJob: Job? = null

    val favoriteIds = container.library.observeFavoriteIds()
        .stateIn(viewModelScope, kotlinx.coroutines.flow.SharingStarted.WhileSubscribed(5_000), emptySet())

    private val _messages = MutableSharedFlow<String>(extraBufferCapacity = 4)
    val messages = _messages.asSharedFlow()

    init {
        viewModelScope.launch {
            container.library.observeSearchHistory().collect { history ->
                _state.update { it.copy(history = history) }
            }
        }
        viewModelScope.launch {
            val hot = runCatching { container.netEase.hotSearches() }.getOrDefault(emptyList())
            _state.update { it.copy(hot = hot) }
        }
    }

    fun onQueryChange(value: String) {
        _state.update { it.copy(query = value, error = null) }
        searchJob?.cancel()
        if (value.isBlank()) {
            _state.update {
                it.copy(songs = emptyList(), artists = emptyList(), albums = emptyList(), playlists = emptyList(), total = 0, page = 1, loading = false)
            }
            return
        }
        searchJob = viewModelScope.launch {
            delay(350)
            runSearch(reset = true)
        }
    }

    fun submit() {
        searchJob?.cancel()
        searchJob = viewModelScope.launch { runSearch(reset = true) }
    }

    fun setMode(mode: SearchMode) {
        if (_state.value.mode == mode) return
        _state.update {
            it.copy(mode = mode, songs = emptyList(), artists = emptyList(), albums = emptyList(), playlists = emptyList(), total = 0, page = 1)
        }
        if (_state.value.query.isNotBlank()) {
            searchJob?.cancel()
            searchJob = viewModelScope.launch { runSearch(reset = true) }
        }
    }

    fun loadMore() {
        val current = _state.value
        if (current.loading || !current.hasMore) return
        searchJob?.cancel()
        searchJob = viewModelScope.launch { runSearch(reset = false) }
    }

    fun useSuggestion(value: String) {
        onQueryChange(value)
        submit()
    }

    fun removeHistory(value: String) {
        viewModelScope.launch { container.library.removeSearchHistory(value) }
    }

    fun clearHistory() {
        viewModelScope.launch { container.library.clearSearchHistory() }
    }

    fun play(index: Int, shuffle: Boolean = false) {
        val tracks = _state.value.songs
        if (tracks.isEmpty()) return
        val ordered = if (shuffle) tracks.shuffled() else tracks
        val start = if (shuffle) 0 else index.coerceIn(0, tracks.lastIndex)
        viewModelScope.launch {
            val quality = container.settings.snapshot().quality
            container.playerConnection.setShuffle(shuffle)
            container.playerConnection.playTracks(ordered, start, quality)
        }
    }

    fun toggleFavorite(track: Track) {
        viewModelScope.launch {
            val added = container.library.toggleFavorite(track)
            _messages.emit(if (added) "已加入收藏" else "已取消收藏")
        }
    }

    fun playNext(track: Track) {
        viewModelScope.launch {
            container.playerConnection.addNext(track, container.settings.snapshot().quality)
            _messages.emit("已设为下一首播放")
        }
    }

    fun enqueue(track: Track) {
        viewModelScope.launch {
            container.playerConnection.enqueue(track, container.settings.snapshot().quality)
            _messages.emit("已加入待播")
        }
    }

    private suspend fun runSearch(reset: Boolean) {
        val snapshot = _state.value
        val query = snapshot.query.trim()
        if (query.isEmpty()) return
        val page = if (reset) 1 else snapshot.page + 1
        _state.update { it.copy(loading = true, error = null) }
        try {
            when (snapshot.mode) {
                SearchMode.SONGS -> {
                    val result = if (container.chksz.hasKey) {
                        runCatching { container.chksz.search(query, page) }
                            .getOrElse { error ->
                                if (error is SourceException.Network) throw error
                                container.netEase.searchSongs(query, offset = (page - 1) * SearchMode.SONGS.pageSize)
                            }
                    } else {
                        container.netEase.searchSongs(query, offset = (page - 1) * SearchMode.SONGS.pageSize)
                    }
                    _state.update {
                        it.copy(
                            loading = false,
                            songs = if (reset) result.items else (it.songs + result.items).distinctBy(Track::musicId),
                            total = result.total,
                            page = page,
                        )
                    }
                }

                SearchMode.ARTISTS -> {
                    val (items, total) = container.netEase.searchArtists(
                        query,
                        limit = SearchMode.ARTISTS.pageSize,
                        offset = (page - 1) * SearchMode.ARTISTS.pageSize,
                    )
                    _state.update {
                        it.copy(
                            loading = false,
                            artists = if (reset) items else (it.artists + items).distinctBy(ArtistSummary::stableId),
                            total = total,
                            page = page,
                        )
                    }
                }

                SearchMode.ALBUMS -> {
                    val (items, total) = container.netEase.searchAlbums(
                        query,
                        limit = SearchMode.ALBUMS.pageSize,
                        offset = (page - 1) * SearchMode.ALBUMS.pageSize,
                    )
                    _state.update {
                        it.copy(
                            loading = false,
                            albums = if (reset) items else (it.albums + items).distinctBy(AlbumSummary::stableId),
                            total = total,
                            page = page,
                        )
                    }
                }

                SearchMode.PLAYLISTS -> {
                    val (items, total) = container.netEase.searchPlaylists(
                        query,
                        limit = SearchMode.PLAYLISTS.pageSize,
                        offset = (page - 1) * SearchMode.PLAYLISTS.pageSize,
                    )
                    _state.update {
                        it.copy(
                            loading = false,
                            playlists = if (reset) items else (it.playlists + items).distinctBy(PlaylistSummary::key),
                            total = total,
                            page = page,
                        )
                    }
                }
            }
            if (reset) container.library.addSearchHistory(query)
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            _state.update {
                it.copy(
                    loading = false,
                    error = (error as? SourceException)?.message ?: error.message ?: "搜索失败",
                )
            }
        }
    }
}
