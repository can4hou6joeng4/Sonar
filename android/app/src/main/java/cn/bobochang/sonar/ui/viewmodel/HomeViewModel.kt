package cn.bobochang.sonar.ui.viewmodel

import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import cn.bobochang.sonar.data.library.UserPlaylist
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.di.AppContainer
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

class HomeViewModel(private val container: AppContainer) : ViewModel() {
    val favorites: StateFlow<List<Track>> = container.library.observeFavorites()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val recent: StateFlow<List<Track>> = container.library.observeRecent()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val playlists: StateFlow<List<UserPlaylist>> = container.library.observePlaylists()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val playerState = container.playerConnection.state

    private val _messages = MutableSharedFlow<String>(extraBufferCapacity = 4)
    val messages = _messages.asSharedFlow()

    fun play(tracks: List<Track>, index: Int, shuffle: Boolean = false) {
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
            val quality = container.settings.snapshot().quality
            container.playerConnection.addNext(track, quality)
            _messages.emit("已设为下一首播放")
        }
    }

    fun enqueue(track: Track) {
        viewModelScope.launch {
            val quality = container.settings.snapshot().quality
            container.playerConnection.enqueue(track, quality)
            _messages.emit("已加入待播")
        }
    }

    fun importLocalUris(uris: List<Uri>) {
        if (uris.isEmpty()) return
        viewModelScope.launch {
            val tracks = container.localImporter.importUris(uris)
            var added = 0
            tracks.forEach { track ->
                runCatching {
                    container.library.addFavorite(track)
                    added++
                }
            }
            _messages.emit(
                if (tracks.isEmpty()) "没有读到可播放的本地音频"
                else "已导入 $added 首本地歌曲",
            )
        }
    }

    fun importLocalTree(uri: Uri) {
        viewModelScope.launch {
            val tracks = container.localImporter.importTree(uri)
            var added = 0
            tracks.forEach { track ->
                runCatching {
                    container.library.addFavorite(track)
                    added++
                }
            }
            _messages.emit(
                if (tracks.isEmpty()) "文件夹中没有可导入的音频"
                else "已导入 $added 首本地歌曲",
            )
        }
    }
}
