package cn.bobochang.sonar.playback

import android.app.PendingIntent
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.ResolvingDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import cn.bobochang.sonar.SonarApplication
import cn.bobochang.sonar.data.model.Quality
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.data.model.wire
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import java.io.IOException

class SonarPlaybackService : MediaSessionService() {
    private lateinit var player: ExoPlayer
    private lateinit var session: MediaSession
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var prefetchJob: Job? = null
    private val prefetchTracks = linkedMapOf<String, Job>()
    private var prefetchEnabled = false

    private val container get() = (application as SonarApplication).container

    override fun onCreate() {
        super.onCreate()

        val resolver = ResolvingDataSource.Resolver { dataSpec ->
            if (dataSpec.uri.scheme == "sonar") {
                val segments = dataSpec.uri.pathSegments
                val quality = Quality.fromWire(segments.getOrNull(0)) ?: Quality.MASTER
                val trackJson = segments.getOrNull(1)
                    ?: throw IOException("播放请求缺少曲目信息")
                val track = Track.fromJson(trackJson)
                    ?: throw IOException("播放请求中的曲目信息无效")
                val resolved = runBlocking { container.playback.resolve(track, quality) }
                dataSpec.withUri(resolved.uri)
            } else {
                dataSpec
            }
        }

        val httpFactory = DefaultHttpDataSource.Factory()
            .setUserAgent(USER_AGENT)
            .setConnectTimeoutMs(15_000)
            .setReadTimeoutMs(30_000)
            .setAllowCrossProtocolRedirects(true)
        val defaultDataSource = DefaultDataSource.Factory(this, httpFactory)
        val resolvingDataSource = ResolvingDataSource.Factory(defaultDataSource, resolver)
        val mediaSourceFactory = DefaultMediaSourceFactory(resolvingDataSource)

        player = ExoPlayer.Builder(this)
            .setMediaSourceFactory(mediaSourceFactory)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(C.USAGE_MEDIA)
                    .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                    .build(),
                true,
            )
            .setHandleAudioBecomingNoisy(true)
            .setWakeMode(C.WAKE_MODE_NETWORK)
            .build()
        player.volume = 1f

        player.addListener(object : Player.Listener {
            override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
                trackOf(mediaItem)?.let { track ->
                    scope.launch { container.library.recordPlay(track) }
                }
                schedulePrefetch()
            }

            override fun onIsPlayingChanged(isPlaying: Boolean) {
                if (isPlaying) schedulePrefetch()
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                schedulePrefetch()
            }

            override fun onTimelineChanged(timeline: androidx.media3.common.Timeline, reason: Int) {
                schedulePrefetch()
            }

            override fun onPlayerError(error: PlaybackException) {
                // Media3 会把错误传给控制端；这里不输出播放地址或凭据。
            }
        })

        session = MediaSession.Builder(this, player)
            .setCallback(object : MediaSession.Callback {
                override fun onConnect(
                    session: MediaSession,
                    controller: MediaSession.ControllerInfo,
                ): MediaSession.ConnectionResult {
                    val allowed = controller.packageName == packageName || controller.isTrusted
                    return if (allowed) {
                        MediaSession.ConnectionResult.AcceptedResultBuilder(session).build()
                    } else {
                        MediaSession.ConnectionResult.reject()
                    }
                }
            })
            .apply {
                packageManager.getLaunchIntentForPackage(packageName)?.let { intent ->
                    val pending = PendingIntent.getActivity(
                        this@SonarPlaybackService,
                        0,
                        intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                    )
                    setSessionActivity(pending)
                }
            }
            .build()

        scope.launch {
            container.settings.settings.collect { settings ->
                prefetchEnabled = settings.autoCache
                schedulePrefetch()
            }
        }
        scope.launch {
            container.connectivity.changes.collect { schedulePrefetch() }
        }
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession = session

    override fun onTaskRemoved(rootIntent: Intent?) {
        if (!player.playWhenReady || player.mediaItemCount == 0) {
            stopSelf()
        }
    }

    override fun onDestroy() {
        prefetchJob?.cancel()
        session.release()
        player.release()
        scope.cancel()
        super.onDestroy()
    }

    private fun schedulePrefetch() {
        prefetchJob?.cancel()
        val index = player.currentMediaItemIndex
        val tracks = if (prefetchEnabled && container.connectivity.isUnmetered() &&
            index >= 0 && index < player.mediaItemCount
        ) {
            (index until minOf(player.mediaItemCount, index + 4)).mapNotNull { itemIndex ->
                val item = player.getMediaItemAt(itemIndex)
                val track = trackOf(item) ?: return@mapNotNull null
                if (track.source == cn.bobochang.sonar.data.model.MusicSource.LOCAL || !track.source.isEnabled) {
                    return@mapNotNull null
                }
                val quality = qualityOf(item) ?: Quality.MASTER
                "${track.musicId}|${quality.wire}" to (track to quality)
            }.toMap()
        } else emptyMap()

        // 换歌只取消离开窗口的任务；开始播放等重复事件不丢弃已下载的进度。
        prefetchTracks.keys.filter { it !in tracks }.forEach { key ->
            prefetchTracks.remove(key)?.cancel()
        }
        prefetchTracks.values.removeAll { !it.isActive }
        if (tracks.isEmpty()) return
        // 播放解析和首段缓冲先行；已开始的整文件下载不随短暂 rebuffer 重启。
        if (player.playbackState != Player.STATE_READY || !player.playWhenReady) return
        prefetchJob = scope.launch {
            delay(1_200)
            if (player.playbackState != Player.STATE_READY || !player.playWhenReady) return@launch
            for ((key, pair) in tracks) {
                if (prefetchTracks[key]?.isActive == true) continue
                val (track, quality) = pair
                prefetchTracks[key] = scope.launch {
                    container.playback.prefetch(listOf(track), quality)
                }
            }
        }
    }

    private fun extrasOf(item: MediaItem?): Bundle? =
        item?.mediaMetadata?.extras ?: (item?.localConfiguration?.tag as? Bundle)

    private fun trackOf(item: MediaItem?): Track? =
        extrasOf(item)?.getString(KEY_TRACK)?.let(Track::fromJson)

    private fun qualityOf(item: MediaItem): Quality? =
        Quality.fromWire(extrasOf(item)?.getString(KEY_QUALITY))

    private companion object {
        const val KEY_TRACK = "track_json"
        const val KEY_QUALITY = "quality"
        const val USER_AGENT =
            "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36"
    }
}
