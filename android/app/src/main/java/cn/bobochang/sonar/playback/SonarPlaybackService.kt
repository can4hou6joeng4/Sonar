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
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import java.io.IOException

class SonarPlaybackService : MediaSessionService() {
    private lateinit var player: ExoPlayer
    private lateinit var session: MediaSession
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var prefetchJob: Job? = null

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
            .setWakeMode(C.WAKE_MODE_LOCAL)
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
        prefetchJob = scope.launch {
            delay(1_200)
            if (player.mediaItemCount == 0) return@launch
            val index = player.currentMediaItemIndex
            if (index < 0) return@launch
            val quality = qualityOf(player.getMediaItemAt(index)) ?: Quality.MASTER
            val end = minOf(player.mediaItemCount, index + 4)
            val tracks = (index until end).mapNotNull { itemIndex ->
                trackOf(player.getMediaItemAt(itemIndex))
            }
            if (tracks.isNotEmpty()) {
                container.playback.prefetch(tracks, quality)
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
