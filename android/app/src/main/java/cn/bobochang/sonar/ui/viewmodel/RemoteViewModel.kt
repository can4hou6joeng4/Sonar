package cn.bobochang.sonar.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import cn.bobochang.sonar.data.library.BackupTarget
import cn.bobochang.sonar.data.model.AlbumSummary
import cn.bobochang.sonar.data.model.ArtistSummary
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.data.net.SourceException
import cn.bobochang.sonar.di.AppContainer
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class RemoteUiState(
    val loading: Boolean = false,
    val error: String? = null,
    val title: String = "",
    val subtitle: String = "",
    val imageUrl: String? = null,
    val description: String? = null,
    val total: Int = 0,
    val tracks: List<Track> = emptyList(),
    val albums: List<AlbumSummary> = emptyList(),
    val isPlaylist: Boolean = false,
)

class RemoteViewModel(private val container: AppContainer) : ViewModel() {
    private val _state = MutableStateFlow(RemoteUiState())
    val state: StateFlow<RemoteUiState> = _state.asStateFlow()

    private val _messages = MutableSharedFlow<String>(extraBufferCapacity = 4)
    val messages = _messages.asSharedFlow()

    val favoriteIds: StateFlow<Set<String>> = container.library.observeFavoriteIds()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptySet())

    private var loadJob: Job? = null

    fun loadPlaylist(id: String) {
        startLoad {
            val playlist = container.netEase.playlistDetail(id)
            _state.value = RemoteUiState(
                title = playlist.name,
                subtitle = listOf(playlist.author, "${playlist.total} 首").filter { it.isNotBlank() }.joinToString(" · "),
                imageUrl = playlist.imageUrl,
                description = playlist.description,
                total = playlist.total,
                tracks = playlist.tracks,
                isPlaylist = true,
            )
        }
    }

    fun loadArtist(id: String) {
        startLoad {
            val (artist, tracks) = container.netEase.artist(id)
            val albums = runCatching { container.netEase.artistAlbums(id) }.getOrDefault(emptyList())
            _state.value = RemoteUiState(
                title = artist.name,
                subtitle = "${tracks.size} 首热门歌曲",
                imageUrl = artist.imageUrl,
                total = tracks.size,
                tracks = tracks,
                albums = albums,
            )
        }
    }

    fun loadAlbum(id: String) {
        startLoad {
            val (album, tracks) = container.netEase.album(id)
            _state.value = RemoteUiState(
                title = album.name,
                subtitle = listOf(album.artist, album.releaseDate ?: "").filter { it.isNotBlank() }.joinToString(" · "),
                imageUrl = album.imageUrl,
                total = tracks.size,
                tracks = tracks,
            )
        }
    }

    fun play(index: Int, shuffle: Boolean = false) {
        val tracks = _state.value.tracks
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

    fun importPlaylist(target: BackupTarget) {
        val snapshot = _state.value
        if (snapshot.tracks.isEmpty()) return
        viewModelScope.launch {
            runCatching {
                container.library.importTracks(target, snapshot.title.ifBlank { "导入的歌单" }, snapshot.tracks)
            }.onSuccess { result ->
                _messages.emit("已导入 ${result.inserted} 首，跳过 ${result.skipped} 首")
            }.onFailure { error ->
                _messages.emit(error.message ?: "导入失败")
            }
        }
    }

    private fun startLoad(block: suspend () -> Unit) {
        loadJob?.cancel()
        _state.value = RemoteUiState(loading = true)
        loadJob = viewModelScope.launch {
            try {
                block()
            } catch (error: CancellationException) {
                throw error
            } catch (error: Throwable) {
                _state.update {
                    it.copy(
                        loading = false,
                        error = (error as? SourceException)?.message ?: error.message ?: "加载失败",
                    )
                }
            }
        }
    }
}
