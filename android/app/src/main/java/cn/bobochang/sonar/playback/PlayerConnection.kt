package cn.bobochang.sonar.playback

import android.content.ComponentName
import android.content.Context
import android.net.Uri
import android.os.Bundle
import androidx.core.content.ContextCompat
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import cn.bobochang.sonar.data.model.Quality
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.data.model.wire
import cn.bobochang.sonar.data.net.SourceException
import cn.bobochang.sonar.data.playback.PlaybackResolution
import cn.bobochang.sonar.data.playback.PlaybackRepository
import com.google.common.util.concurrent.ListenableFuture
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

enum class PlaybackMode(val title: String) {
    SEQUENCE("列表循环"),
    PLAY_IN_ORDER("顺序播放"),
    SHUFFLE("随机播放"),
    REPEAT_ONE("单曲循环");

    val next: PlaybackMode
        get() = when (this) {
            SHUFFLE -> REPEAT_ONE
            REPEAT_ONE -> PLAY_IN_ORDER
            PLAY_IN_ORDER -> SEQUENCE
            SEQUENCE -> SHUFFLE
        }
}

data class PlayerUiState(
    val connected: Boolean = false,
    val isPlaying: Boolean = false,
    val isLoading: Boolean = false,
    val playWhenReady: Boolean = false,
    val positionMs: Long = 0L,
    val durationMs: Long = 0L,
    val track: Track? = null,
    val index: Int = -1,
    val count: Int = 0,
    val queue: List<Track> = emptyList(),
    val playbackMode: PlaybackMode = PlaybackMode.SEQUENCE,
    val playbackRate: Float = 1f,
    val actualQuality: Quality? = null,
    val usingCache: Boolean = false,
    val error: String? = null,
) {
    val hasTrack: Boolean get() = track != null
}

class PlayerConnection(
    context: Context,
    private val playback: PlaybackRepository,
) {
    private val appContext = context.applicationContext
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val _state = MutableStateFlow(PlayerUiState())
    val state: StateFlow<PlayerUiState> = _state.asStateFlow()

    private val _sleepMinutes = MutableStateFlow<Int?>(null)
    val sleepMinutes: StateFlow<Int?> = _sleepMinutes.asStateFlow()

    private val _sleepRemainingMs = MutableStateFlow<Long?>(null)
    val sleepRemainingMs: StateFlow<Long?> = _sleepRemainingMs.asStateFlow()

    private var controller: MediaController? = null
    private var controllerFuture: ListenableFuture<MediaController>? = null
    private var connecting = false
    private var ticker: Job? = null
    private var sleepJob: Job? = null
    private var lastResolution: PlaybackResolution? = null
    private var playbackMode = PlaybackMode.SEQUENCE
    private var playbackRate = 1f
    private var sleepDeadline: Long? = null

    private val controllerListener = object : MediaController.Listener {
        override fun onDisconnected(controller: MediaController) {
            controller.removeListener(listener)
            if (this@PlayerConnection.controller === controller) {
                this@PlayerConnection.controller = null
                _state.update { it.copy(connected = false, isPlaying = false, isLoading = false) }
                scope.launch {
                    delay(500)
                    connect()
                }
            }
        }
    }

    private val listener = object : Player.Listener {
        override fun onEvents(player: Player, events: Player.Events) {
            publish(player)
        }

        override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
            _state.update { it.copy(error = null) }
            controller?.let(::publish)
        }

        override fun onPlayerError(error: PlaybackException) {
            _state.update {
                it.copy(error = playbackErrorMessage(error))
            }
        }
    }

    init {
        scope.launch {
            playback.lastResolution.collect { resolution ->
                lastResolution = resolution
                _state.update { state ->
                    state.copy(
                        actualQuality = resolution
                            ?.takeIf { it.musicId == state.track?.musicId }
                            ?.quality,
                        usingCache = resolution
                            ?.takeIf { it.musicId == state.track?.musicId }
                            ?.cached == true,
                    )
                }
            }
        }
        connect()
    }

    private fun connect() {
        if (controller != null || connecting) return
        connecting = true
        val token = SessionToken(
            appContext,
            ComponentName(appContext, SonarPlaybackService::class.java),
        )
        val future = MediaController.Builder(appContext, token)
            .setListener(controllerListener)
            .buildAsync()
        controllerFuture = future
        future.addListener(
            {
                connecting = false
                runCatching { future.get() }
                    .onSuccess { connected ->
                        controller = connected
                        connected.addListener(listener)
                        connected.setPlaybackSpeed(playbackRate)
                        applyPlaybackMode(connected, playbackMode)
                        publish(connected)
                        startTicker()
                    }
                    .onFailure {
                        _state.update { state ->
                            state.copy(connected = false, error = "播放服务连接失败")
                        }
                    }
            },
            ContextCompat.getMainExecutor(appContext),
        )
    }

    fun playTracks(tracks: List<Track>, startIndex: Int, quality: Quality) {
        val player = controller ?: return
        if (tracks.isEmpty()) return
        val items = tracks.map { itemFor(it, quality) }
        player.setMediaItems(items, startIndex.coerceIn(0, items.lastIndex), 0L)
        player.prepare()
        player.play()
    }

    fun playAt(index: Int) {
        val player = controller ?: return
        if (index in 0 until player.mediaItemCount) {
            player.seekToDefaultPosition(index)
            player.play()
        }
    }

    fun selectQueueItem(index: Int) = playAt(index)

    fun toggle() {
        val player = controller ?: return
        if (player.isPlaying) {
            player.pause()
            return
        }
        if (player.playbackState == Player.STATE_IDLE) {
            player.prepare()
        } else if (player.playbackState == Player.STATE_ENDED) {
            player.seekTo(0)
        }
        player.play()
    }

    fun next() {
        controller?.seekToNextMediaItem()
    }

    fun previous() {
        controller?.seekToPreviousMediaItem()
    }

    fun pause() {
        controller?.pause()
    }

    fun retry() {
        val player = controller ?: return
        _state.update { it.copy(error = null) }
        player.prepare()
        player.play()
    }

    fun setSleepTimer(minutes: Int?) {
        sleepJob?.cancel()
        sleepJob = null
        if (minutes == null) {
            sleepDeadline = null
            _sleepMinutes.value = null
            _sleepRemainingMs.value = null
            return
        }
        _sleepMinutes.value = minutes
        val totalMs = minutes.coerceAtLeast(1) * 60_000L
        val deadline = System.currentTimeMillis() + totalMs
        sleepDeadline = deadline
        _sleepRemainingMs.value = totalMs
        sleepJob = scope.launch {
            while (isActive) {
                val remaining = deadline - System.currentTimeMillis()
                if (remaining <= 0) break
                _sleepRemainingMs.value = remaining
                delay(1_000)
            }
            controller?.pause()
            sleepDeadline = null
            _sleepMinutes.value = null
            _sleepRemainingMs.value = null
        }
    }

    fun seekTo(positionMs: Long) {
        controller?.seekTo(positionMs.coerceAtLeast(0))
    }

    fun addNext(track: Track, quality: Quality) {
        val player = controller ?: return
        if (player.mediaItemCount == 0) {
            playTracks(listOf(track), 0, quality)
            return
        }
        val index = (player.currentMediaItemIndex + 1).coerceIn(0, player.mediaItemCount)
        player.addMediaItem(index, itemFor(track, quality))
    }

    fun enqueue(track: Track, quality: Quality) {
        val player = controller ?: return
        if (player.mediaItemCount == 0) {
            playTracks(listOf(track), 0, quality)
            return
        }
        player.addMediaItem(itemFor(track, quality))
    }

    fun removeAt(index: Int) {
        val player = controller ?: return
        if (index in 0 until player.mediaItemCount) player.removeMediaItem(index)
    }

    fun removeQueueItem(index: Int) = removeAt(index)

    fun clearUpcoming() {
        val player = controller ?: return
        val index = player.currentMediaItemIndex
        if (index >= 0 && index < player.mediaItemCount - 1) {
            player.removeMediaItems(index + 1, player.mediaItemCount)
        }
    }

    fun move(from: Int, to: Int) {
        controller?.moveMediaItem(from, to)
    }

    /** iOS `moveMediaItems(fromOffsets:toOffset:)` 的插入语义。 */
    fun moveQueueItems(fromIndex: Int, insertionOffset: Int) {
        val player = controller ?: return
        val count = player.mediaItemCount
        if (fromIndex !in 0 until count) return
        val target = insertionOffset.coerceIn(0, count)
        val destination = if (target > fromIndex) target - 1 else target
        player.moveMediaItem(fromIndex, destination.coerceIn(0, count - 1))
    }

    fun setPlaybackMode(mode: PlaybackMode) {
        playbackMode = mode
        _state.update { it.copy(playbackMode = mode) }
        controller?.let { applyPlaybackMode(it, mode) }
    }

    fun cyclePlaybackMode() = setPlaybackMode(playbackMode.next)

    fun setPlaybackRate(rate: Float) {
        playbackRate = rate
        _state.update { it.copy(playbackRate = rate) }
        controller?.setPlaybackSpeed(rate)
    }

    fun toggleShuffle() {
        setPlaybackMode(if (playbackMode == PlaybackMode.SHUFFLE) PlaybackMode.SEQUENCE else PlaybackMode.SHUFFLE)
    }

    fun setShuffle(enabled: Boolean) {
        if (enabled) setPlaybackMode(PlaybackMode.SHUFFLE) else setPlaybackMode(PlaybackMode.SEQUENCE)
    }

    fun cycleRepeat() {
        setPlaybackMode(
            when (playbackMode) {
                PlaybackMode.SEQUENCE, PlaybackMode.SHUFFLE -> PlaybackMode.REPEAT_ONE
                PlaybackMode.REPEAT_ONE -> PlaybackMode.PLAY_IN_ORDER
                PlaybackMode.PLAY_IN_ORDER -> PlaybackMode.SEQUENCE
            },
        )
    }

    /** 切换音质后就地重新解析当前曲目，保留播放进度。 */
    fun reloadAtQuality(track: Track, quality: Quality) {
        val player = controller ?: return
        val index = player.currentMediaItemIndex
        if (index !in 0 until player.mediaItemCount) {
            playTracks(listOf(track), 0, quality)
            return
        }
        val position = player.currentPosition.coerceAtLeast(0)
        val shouldPlay = player.playWhenReady
        player.replaceMediaItem(index, itemFor(track, quality))
        player.prepare()
        player.seekTo(index, position)
        if (shouldPlay) player.play()
    }

    fun queue(): List<Track> {
        val player = controller ?: return emptyList()
        return (0 until player.mediaItemCount).mapNotNull { index ->
            trackOf(player.getMediaItemAt(index))
        }
    }

    fun currentQuality(): Quality? {
        val player = controller ?: return null
        val index = player.currentMediaItemIndex
        if (index !in 0 until player.mediaItemCount) return null
        val item = player.getMediaItemAt(index)
        return Quality.fromWire(extrasOf(item)?.getString(KEY_QUALITY))
    }

    fun release() {
        ticker?.cancel()
        sleepJob?.cancel()
        controller?.removeListener(listener)
        controller = null
        controllerFuture?.let { MediaController.releaseFuture(it) }
        controllerFuture = null
        scope.cancel()
    }

    private fun applyPlaybackMode(player: Player, mode: PlaybackMode) {
        when (mode) {
            PlaybackMode.SEQUENCE -> {
                player.shuffleModeEnabled = false
                player.repeatMode = Player.REPEAT_MODE_ALL
            }

            PlaybackMode.PLAY_IN_ORDER -> {
                player.shuffleModeEnabled = false
                player.repeatMode = Player.REPEAT_MODE_OFF
            }

            PlaybackMode.SHUFFLE -> {
                player.shuffleModeEnabled = true
                player.repeatMode = Player.REPEAT_MODE_ALL
            }

            PlaybackMode.REPEAT_ONE -> {
                player.shuffleModeEnabled = false
                player.repeatMode = Player.REPEAT_MODE_ONE
            }
        }
    }

    private fun publish(player: Player) {
        val count = player.mediaItemCount
        val hasItem = count > 0 && player.currentMediaItemIndex in 0 until count
        val item = if (hasItem) player.getMediaItemAt(player.currentMediaItemIndex) else null
        val track = item?.let(::trackOf)
        val queue = if (count > 0) {
            (0 until count).mapNotNull { index -> trackOf(player.getMediaItemAt(index)) }
        } else {
            emptyList()
        }
        val resolution = lastResolution?.takeIf { it.musicId == track?.musicId }
        _state.update { state ->
            state.copy(
                connected = true,
                isPlaying = player.isPlaying,
                isLoading = player.playbackState == Player.STATE_BUFFERING,
                playWhenReady = player.playWhenReady,
                positionMs = player.currentPosition.coerceAtLeast(0),
                durationMs = player.duration.takeIf { it > 0 } ?: track?.durationMs ?: 0L,
                track = track,
                index = if (hasItem) player.currentMediaItemIndex else -1,
                count = count,
                queue = queue,
                playbackMode = playbackMode,
                playbackRate = playbackRate,
                actualQuality = resolution?.quality,
                usingCache = resolution?.cached == true,
            )
        }
    }

    private fun startTicker() {
        if (ticker != null) return
        ticker = scope.launch {
            while (isActive) {
                val player = controller
                if (player != null && player.mediaItemCount > 0) {
                    _state.update { state ->
                        state.copy(
                            positionMs = player.currentPosition.coerceAtLeast(0),
                            durationMs = player.duration.takeIf { it > 0 } ?: state.durationMs,
                            isPlaying = player.isPlaying,
                            isLoading = player.playbackState == Player.STATE_BUFFERING,
                            playWhenReady = player.playWhenReady,
                        )
                    }
                }
                delay(500)
            }
        }
    }

    private fun itemFor(track: Track, quality: Quality): MediaItem {
        val json = track.toJson()
        val extras = Bundle().apply {
            putString(KEY_TRACK, json)
            putString(KEY_QUALITY, quality.wire)
        }
        val metadata = MediaMetadata.Builder()
            .setTitle(track.title)
            .setArtist(track.artist)
            .setAlbumTitle(track.album)
            .setIsBrowsable(false)
            .setIsPlayable(true)
            .setExtras(extras)
            .apply { track.coverUrl?.let { setArtworkUri(Uri.parse(it)) } }
            .build()
        val tag = Bundle().apply {
            putString(KEY_TRACK, json)
            putString(KEY_QUALITY, quality.wire)
        }
        return MediaItem.Builder()
            .setMediaId(track.musicId)
            .setUri("sonar://track/${quality.wire}/${Uri.encode(json)}")
            .setMediaMetadata(metadata)
            .setTag(tag)
            .build()
    }

    /** 优先从 MediaMetadata.extras 读取，控制器侧拿不到 MediaItem 的私有 tag。 */
    private fun extrasOf(item: MediaItem): Bundle? =
        item.mediaMetadata.extras ?: (item.localConfiguration?.tag as? Bundle)

    private fun trackOf(item: MediaItem): Track? =
        extrasOf(item)?.getString(KEY_TRACK)?.let(Track::fromJson)

    /** Media3 的错误信息可能带完整 sonar:// URI，只把可读的原因透出到界面。 */
    private fun playbackErrorMessage(error: PlaybackException): String {
        var cause: Throwable? = error
        while (cause != null) {
            if (cause is SourceException) {
                return cause.message?.takeIf { it.isNotBlank() } ?: "播放失败"
            }
            cause = cause.cause
        }
        return "播放失败，请检查网络、账号权限或稍后重试"
    }

    private companion object {
        const val KEY_TRACK = "track_json"
        const val KEY_QUALITY = "quality"
    }
}
