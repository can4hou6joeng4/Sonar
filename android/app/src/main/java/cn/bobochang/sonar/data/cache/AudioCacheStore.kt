package cn.bobochang.sonar.data.cache

import android.content.Context
import android.os.StatFs
import cn.bobochang.sonar.data.library.CachedAudioEntity
import cn.bobochang.sonar.data.library.LibraryDao
import cn.bobochang.sonar.data.model.MusicSource
import cn.bobochang.sonar.data.model.Quality
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.data.model.wire
import cn.bobochang.sonar.data.net.SonarHttp
import cn.bobochang.sonar.data.net.awaitResponse
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.job
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.ConcurrentHashMap

class AudioCacheStore internal constructor(
    private val cacheDir: File,
    private val dao: LibraryDao,
    private val client: OkHttpClient = SonarHttp.downloadClient,
    private val hasSpace: () -> Boolean = {
        StatFs(cacheDir.absolutePath).availableBytes >= MIN_FREE_BYTES
    },
) {
    constructor(context: Context, dao: LibraryDao) : this(File(context.filesDir, "audio_cache"), dao)

    private data class Download(val result: CompletableDeferred<File?>, val job: Job)

    private val inFlight = ConcurrentHashMap<String, Download>()
    // 与「当前＋后 3 首」预取窗口一致；仍为有界并发，避免过度挤占播放缓冲。
    private val downloadSlots = Semaphore(4)
    private val writes = Mutex()
    private var generation = 0L

    init { cacheDir.mkdirs() }

    fun observeCount(): Flow<Int> = dao.observeCacheCount()

    fun observeBytes(): Flow<Long> = dao.observeCacheBytes()

    data class CachedFile(val file: File, val quality: Quality)

    suspend fun bestCached(musicId: String, maxQuality: Quality): CachedFile? = withContext(Dispatchers.IO) {
        val entries = dao.cachedFor(musicId)
            .filter { Quality.fromWire(it.quality)?.rank?.let { rank -> rank <= maxQuality.rank } == true }
            .sortedByDescending { Quality.fromWire(it.quality)?.rank ?: 0 }
        for (entry in entries) {
            val file = File(cacheDir, entry.fileName)
            if (file.isFile && file.length() > 0 && file.length() == entry.size) {
                return@withContext CachedFile(file, Quality.fromWire(entry.quality) ?: Quality.STANDARD)
            }
            dao.deleteCached(entry.cacheKey)
        }
        null
    }

    /**
     * 所有调用共用同一下载和全局并发限额；取消等待者不会取消其他调用的下载。
     * 登记的 Job 是本次 withContext 块自身的 Job，clear() 只取消这一次调用，
     * 调用方会收到 CancellationException，其所在 scope 不受影响。
     */
    suspend fun download(
        track: Track,
        url: String,
        quality: Quality,
        canDownload: () -> Boolean = { true },
    ): File? = withContext(Dispatchers.IO) {
        if (track.source == MusicSource.LOCAL) return@withContext null
        val key = cacheKey(track, quality)
        val downloadGeneration = writes.withLock { generation }
        while (true) {
            currentCoroutineContext().ensureActive()
            val flight = Download(CompletableDeferred(), currentCoroutineContext().job)
            val previous = writes.withLock {
                if (generation != downloadGeneration) return@withContext null
                inFlight.putIfAbsent(key, flight)
            }
            if (previous != null) {
                try {
                    return@withContext previous.result.await()
                } catch (error: CancellationException) {
                    // 拥有者退出队列时，仍需要此曲的调用可重新接手。
                    currentCoroutineContext().ensureActive()
                    continue
                }
            }
            try {
                val file = downloadSlots.withPermit { downloadFile(track, url, quality, canDownload) }
                flight.result.complete(file)
                return@withContext file
            } catch (error: CancellationException) {
                flight.result.cancel(error)
                throw error
            } catch (_: Exception) {
                flight.result.complete(null)
                return@withContext null
            } finally {
                inFlight.remove(key, flight)
            }
        }
        @Suppress("UNREACHABLE_CODE")
        null
    }

    private suspend fun downloadFile(
        track: Track,
        url: String,
        quality: Quality,
        canDownload: () -> Boolean,
    ): File? {
        val key = cacheKey(track, quality)
        bestCached(track.musicId, quality)?.takeIf { it.quality == quality }?.let { return it.file }
        if (!canDownload() || !hasSpace()) return null

        val extension = extensionFor(url)
        val safeName = track.musicId.replace(Regex("[^A-Za-z0-9._-]"), "_").take(120)
        val fileName = "$safeName-${quality.wire}.$extension"
        val target = File(cacheDir, fileName)
        // 唯一临时文件防止旧 HTTP 回调的收尾影响接手下载。
        val temp = File.createTempFile("dl-$safeName-", ".part", cacheDir)
        val context = currentCoroutineContext()
        try {
            val request = SonarHttp.mediaRequest(url).get().build()
            val complete = client.newCall(request).awaitResponse { response ->
                try {
                    context.ensureActive()
                    // GET 必须返回整文件，206 的局部响应即使长度匹配也不能入库。
                    if (response.code != 200 || response.header("Content-Range") != null) return@awaitResponse false
                    val contentType = response.header("Content-Type")?.lowercase().orEmpty()
                    if (contentType.startsWith("text/") || contentType.contains("html") ||
                        contentType.contains("json") || contentType.contains("xml") ||
                        contentType.contains("mpegurl")
                    ) return@awaitResponse false
                    val body = response.body ?: return@awaitResponse false
                    val expected = body.contentLength()
                    var copied = 0L
                    body.byteStream().use { input ->
                        FileOutputStream(temp).use { output ->
                            val buffer = ByteArray(64 * 1024)
                            while (true) {
                                context.ensureActive()
                                if (!canDownload()) return@awaitResponse false
                                val read = input.read(buffer)
                                if (read < 0) break
                                output.write(buffer, 0, read)
                                copied += read
                            }
                            if (copied <= 0 || (expected >= 0 && copied != expected)) return@awaitResponse false
                            output.fd.sync()
                        }
                    }
                    true
                } finally {
                    if (!context.isActive) temp.delete()
                }
            }
            if (!complete) return null
            return writes.withLock {
                context.ensureActive()
                if (!canDownload()) return@withLock null
                // 完整文件替换与索引提交是一段短的不可取消操作；不先删除已有文件。
                withContext(NonCancellable) {
                    if (!temp.renameTo(target)) return@withContext null
                    dao.insertCached(
                        CachedAudioEntity(key, track.musicId, quality.wire, fileName, target.length(), System.currentTimeMillis()),
                    )
                    target
                }
            }
        } finally {
            temp.delete()
        }
    }

    suspend fun clear(): Pair<Int, Long> = withContext(Dispatchers.IO) {
        writes.withLock {
            generation++
            inFlight.values.forEach { it.job.cancel() }
            val entries = dao.allCached()
            val bytes = entries.sumOf { entry -> File(cacheDir, entry.fileName).length().coerceAtLeast(0) }
            dao.clearCached()
            cacheDir.listFiles()?.forEach { it.delete() }
            entries.size to bytes
        }
    }

    private fun cacheKey(track: Track, quality: Quality): String = "${track.musicId}|${quality.wire}"

    private fun extensionFor(url: String): String {
        val candidate = url.substringBefore('?')
            .substringBefore('#')
            .substringAfterLast('/')
            .substringAfterLast('.', "")
            .lowercase()
        return candidate.takeIf { it in setOf("mp3", "flac", "m4a", "aac", "ogg", "wav", "opus") } ?: "audio"
    }

    private companion object {
        const val MIN_FREE_BYTES = 1_000_000_000L
    }
}
