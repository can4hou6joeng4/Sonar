package cn.bobochang.sonar.data.playback

import android.net.Uri
import cn.bobochang.sonar.data.cache.AudioCacheStore
import cn.bobochang.sonar.data.model.MusicSource
import cn.bobochang.sonar.data.model.Quality
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.data.model.string
import cn.bobochang.sonar.data.model.wire
import cn.bobochang.sonar.data.net.ChkszClient
import cn.bobochang.sonar.data.net.ConnectivityMonitor
import cn.bobochang.sonar.data.net.NetEaseWebClient
import cn.bobochang.sonar.data.net.SourceException
import cn.bobochang.sonar.data.net.probeMediaUrl
import cn.bobochang.sonar.data.prefs.SettingsRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.supervisorScope
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import java.io.File
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap

data class ResolvedSource(
    val uri: Uri,
    val quality: Quality,
    val cached: Boolean,
    val networkUrl: String? = null,
)

data class PlaybackResolution(
    val musicId: String,
    val quality: Quality,
    val cached: Boolean,
)

/**
 * 解析顺序与 iOS 一致：本地文件 → 离线缓存 → 网易云直连（按音质阶梯）→ ChKSz（按音质阶梯）。
 * 网络/凭据错误立即终止；只有"该档不可用"才继续降档。
 */
class PlaybackRepository(
    private val netEase: NetEaseWebClient,
    private val chksz: ChkszClient,
    private val cache: AudioCacheStore,
    private val settings: SettingsRepository,
    private val connectivity: ConnectivityMonitor,
    private val probe: suspend (String) -> Boolean = ::probeMediaUrl,
) {
    private data class CachedUrl(val url: String, val quality: Quality, val expiresAt: Long)

    private val urlCache = ConcurrentHashMap<String, CachedUrl>()
    private val resolving = ConcurrentHashMap<String, CompletableDeferred<ResolvedSource>>()
    private val prefetchSlots = Semaphore(2)
    private val _lastResolution = MutableStateFlow<PlaybackResolution?>(null)

    /** 最近一次真正返回给播放器的音质与缓存标记，供播放页音质面板展示。 */
    val lastResolution: StateFlow<PlaybackResolution?> = _lastResolution.asStateFlow()

    suspend fun resolve(track: Track, requested: Quality): ResolvedSource {
        if (track.source == MusicSource.LOCAL) {
            return recordResolution(track, resolveLocal(track))
        }
        if (!track.source.isEnabled) {
            throw SourceException.Unavailable("${track.source.displayName}音源暂不可用，歌曲仍保留在资料库")
        }

        val cached = cache.bestCached(track.musicId, requested)
        val snapshot = settings.snapshot()
        val online = connectivity.isOnline()
        val cellularRestricted = snapshot.cellularWifiOnly && connectivity.isCellular()

        if (cached != null && (!online || cellularRestricted || cached.quality.rank >= requested.rank)) {
            return recordResolution(track, ResolvedSource(Uri.fromFile(cached.file), cached.quality, cached = true))
        }
        if (cellularRestricted) {
            throw SourceException.Unavailable("蜂窝网络下仅播放已缓存歌曲，可在设置中关闭此限制")
        }
        if (!online) {
            throw SourceException.Network(IOException("当前没有网络连接"))
        }

        val network = try {
            resolveNetwork(track, requested)
        } catch (error: SourceException) {
            if (cached != null) {
                return recordResolution(track, ResolvedSource(Uri.fromFile(cached.file), cached.quality, cached = true))
            }
            throw error
        }

        return recordResolution(track, network)
    }

    private fun recordResolution(track: Track, source: ResolvedSource): ResolvedSource {
        _lastResolution.value = PlaybackResolution(
            musicId = track.musicId,
            quality = source.quality,
            cached = source.cached,
        )
        return source
    }

    suspend fun prefetch(tracks: List<Track>, requested: Quality) = supervisorScope {
        val snapshot = settings.snapshot()
        if (!snapshot.autoCache || !connectivity.isOnline() || !connectivity.isUnmetered()) {
            return@supervisorScope
        }
        tracks.asSequence()
            .filter { it.source != MusicSource.LOCAL && it.source.isEnabled }
            .distinctBy { it.musicId }
            .map { track ->
                async(Dispatchers.IO) {
                    try {
                        prefetchTrack(track, requested)
                    } catch (error: CancellationException) {
                        throw error
                    } catch (_: Exception) {
                        // 预取失败不影响播放；下一次队列调度可重试。
                    }
                }
            }
            .toList()
            .awaitAll()
        Unit
    }

    private suspend fun prefetchTrack(track: Track, requested: Quality) {
        if (!settings.snapshot().autoCache || !connectivity.isUnmetered()) return
        val cached = cache.bestCached(track.musicId, requested)
        if (cached != null && cached.quality.satisfies(requested)) return
        // 音源解析与整文件下载分别限流，后续曲目可在下载期间准备好 URL。
        val resolved = prefetchSlots.withPermit { resolveNetwork(track, requested) }
        if (cached != null && cached.quality.satisfies(resolved.quality)) return
        if (!settings.snapshot().autoCache || !connectivity.isUnmetered()) return
        resolved.networkUrl?.let { url ->
            cache.download(track, url, resolved.quality, canDownload = connectivity::isUnmetered)
        }
    }

    /** 同歌曲/请求档位合并解析；最高档回退结果也记在原请求档位下。 */
    private suspend fun resolveNetwork(track: Track, requested: Quality): ResolvedSource {
        val key = "${track.musicId}|${requested.wire}|requested"
        while (true) {
            currentCoroutineContext().ensureActive()
            val flight = CompletableDeferred<ResolvedSource>()
            val previous = resolving.putIfAbsent(key, flight)
            if (previous != null) {
                try {
                    return previous.await()
                } catch (error: CancellationException) {
                    currentCoroutineContext().ensureActive()
                    continue
                }
            }
            try {
                val resolved = resolveNetworkSteps(track, requested, key)
                flight.complete(resolved)
                return resolved
            } catch (error: Throwable) {
                flight.completeExceptionally(error)
                throw error
            } finally {
                resolving.remove(key, flight)
            }
        }
        @Suppress("UNREACHABLE_CODE")
        throw IllegalStateException("unreachable")
    }

    private suspend fun resolveNetworkSteps(track: Track, requested: Quality, requestedKey: String): ResolvedSource {
        val now = System.currentTimeMillis()
        urlCache[requestedKey]?.takeIf { it.expiresAt > now }?.let { cached ->
            return ResolvedSource(Uri.parse(cached.url), cached.quality, cached = false, networkUrl = cached.url)
        }
        for (quality in Quality.descending.filter { it.rank <= requested.rank }) {
            val key = "${track.musicId}|${quality.wire}"
            urlCache[key]?.takeIf { it.expiresAt > now }?.let { cached ->
                urlCache[requestedKey] = cached
                return ResolvedSource(Uri.parse(cached.url), cached.quality, cached = false, networkUrl = cached.url)
            }

            try {
                val native = netEase.playableUrl(track.songmid, quality)
                if (native != null && native.quality.satisfies(quality) && probe(native.url)) {
                    urlCache[key] = CachedUrl(native.url, native.quality, now + URL_TTL_MS)
                    urlCache[requestedKey] = CachedUrl(native.url, native.quality, now + URL_TTL_MS)
                    return ResolvedSource(
                        uri = Uri.parse(native.url),
                        quality = native.quality,
                        cached = false,
                        networkUrl = native.url,
                    )
                }
            } catch (error: SourceException.Network) {
                throw error
            } catch (error: SourceException.CredentialRequired) {
                throw error
            } catch (_: SourceException) {
                // 直连该档不可用，继续尝试 ChKSz 同档。
            }

            if (chksz.hasKey) {
                try {
                    val remote = chksz.musicUrl(track, quality)
                    if (remote.quality.satisfies(quality) && probe(remote.url)) {
                        urlCache[key] = CachedUrl(remote.url, remote.quality, now + URL_TTL_MS)
                        urlCache[requestedKey] = CachedUrl(remote.url, remote.quality, now + URL_TTL_MS)
                        return ResolvedSource(
                            uri = Uri.parse(remote.url),
                            quality = remote.quality,
                            cached = false,
                            networkUrl = remote.url,
                        )
                    }
                } catch (error: SourceException.Network) {
                    throw error
                } catch (error: SourceException.CredentialRequired) {
                    throw error
                } catch (_: SourceException) {
                    // 继续降档。
                }
            }
        }
        throw SourceException.Unavailable("没有可用播放地址，请检查账号权限或稍后重试")
    }

    private fun resolveLocal(track: Track): ResolvedSource {
        val raw = track.payload.string("uri") ?: track.payload.string("filePath")
            ?: throw SourceException.Unavailable("本地音频路径为空")
        val uri = Uri.parse(raw)
        if (uri.scheme == null && raw.startsWith("/")) {
            val file = File(raw)
            if (!file.exists()) throw SourceException.Unavailable("本地音频文件不存在或已移动")
            return ResolvedSource(Uri.fromFile(file), Quality.STANDARD, cached = true)
        }
        if (uri.scheme == "file") {
            val file = uri.path?.let(::File)
            if (file == null || !file.exists()) {
                throw SourceException.Unavailable("本地音频文件不存在或已移动")
            }
        }
        return ResolvedSource(uri, Quality.STANDARD, cached = true)
    }

    private companion object {
        const val URL_TTL_MS = 20 * 60 * 1000L
    }
}
