package cn.bobochang.sonar.data.cache

import android.content.Context
import android.os.StatFs
import cn.bobochang.sonar.data.library.CachedAudioEntity
import cn.bobochang.sonar.data.library.LibraryDao
import cn.bobochang.sonar.data.model.Quality
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.data.model.wire
import cn.bobochang.sonar.data.net.SonarHttp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.launch
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.ConcurrentHashMap

class AudioCacheStore(
    context: Context,
    private val dao: LibraryDao,
) {
    private val cacheDir = File(context.filesDir, "audio_cache").apply { mkdirs() }
    private val inFlight = ConcurrentHashMap<String, Job>()

    fun observeCount(): Flow<Int> = dao.observeCacheCount()

    fun observeBytes(): Flow<Long> = dao.observeCacheBytes()

    data class CachedFile(val file: File, val quality: Quality)

    suspend fun bestCached(musicId: String, maxQuality: Quality): CachedFile? {
        val entries = dao.cachedFor(musicId)
            .filter { Quality.fromWire(it.quality)?.rank?.let { rank -> rank <= maxQuality.rank } == true }
            .sortedByDescending { Quality.fromWire(it.quality)?.rank ?: 0 }
        for (entry in entries) {
            val file = File(cacheDir, entry.fileName)
            if (file.exists() && file.length() > 0) {
                return CachedFile(file, Quality.fromWire(entry.quality) ?: Quality.STANDARD)
            }
            dao.deleteCached(entry.cacheKey)
        }
        return null
    }

    suspend fun enqueue(scope: CoroutineScope, track: Track, url: String, quality: Quality): Boolean {
        if (track.source == cn.bobochang.sonar.data.model.MusicSource.LOCAL) return false
        val key = cacheKey(track, quality)
        if (inFlight.containsKey(key)) return false
        val job = scope.launch(Dispatchers.IO, start = CoroutineStart.LAZY) {
            try {
                download(track, url, quality)
            } finally {
                inFlight.remove(key)
            }
        }
        val previous = inFlight.putIfAbsent(key, job)
        if (previous != null) {
            job.cancel()
            return false
        }
        job.start()
        return true
    }

    suspend fun download(track: Track, url: String, quality: Quality): File? {
        if (!hasSpace()) return null
        val key = cacheKey(track, quality)
        val existing = dao.cachedFor(track.musicId).firstOrNull { it.cacheKey == key }
        if (existing != null) {
            val file = File(cacheDir, existing.fileName)
            if (file.exists() && file.length() > 0) return file
            dao.deleteCached(key)
        }

        val extension = extensionFor(url)
        val safeName = track.musicId.replace(Regex("[^A-Za-z0-9._-]"), "_").take(120)
        val fileName = "$safeName-${quality.wire}.$extension"
        val target = File(cacheDir, fileName)
        if (target.exists() && target.length() > 0) {
            dao.insertCached(CachedAudioEntity(key, track.musicId, quality.wire, fileName, target.length(), System.currentTimeMillis()))
            return target
        }
        val temp = File(cacheDir, "$fileName.part")
        if (temp.exists()) temp.delete()

        return try {
            val request = SonarHttp.mediaRequest(url).get().build()
            SonarHttp.client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return null
                val contentType = response.header("Content-Type")?.lowercase().orEmpty()
                if (contentType.startsWith("text/") ||
                    contentType.contains("html") ||
                    contentType.contains("json")
                ) {
                    return null
                }
                val body = response.body ?: return null
                val expected = body.contentLength()
                var copied = 0L
                body.byteStream().use { input ->
                    FileOutputStream(temp).use { output ->
                        val buffer = ByteArray(64 * 1024)
                        while (true) {
                            val read = input.read(buffer)
                            if (read < 0) break
                            output.write(buffer, 0, read)
                            copied += read
                        }
                        output.fd.sync()
                    }
                }
                if (copied <= 0 || (expected > 0 && copied != expected)) {
                    temp.delete()
                    return null
                }
                if (target.exists()) target.delete()
                if (!temp.renameTo(target)) {
                    temp.delete()
                    return null
                }
                dao.insertCached(
                    CachedAudioEntity(
                        cacheKey = key,
                        musicId = track.musicId,
                        quality = quality.wire,
                        fileName = fileName,
                        size = target.length(),
                        savedAt = System.currentTimeMillis(),
                    ),
                )
                target
            }
        } catch (_: Throwable) {
            temp.delete()
            null
        }
    }

    suspend fun clear(): Pair<Int, Long> {
        val entries = dao.allCached()
        val count = entries.size
        var bytes = 0L
        entries.forEach { entry ->
            val file = File(cacheDir, entry.fileName)
            bytes += file.length().coerceAtLeast(0)
            file.delete()
        }
        dao.clearCached()
        cacheDir.listFiles()?.forEach { it.delete() }
        return count to bytes
    }

    private fun cacheKey(track: Track, quality: Quality): String = "${track.musicId}|${quality.wire}"

    private fun hasSpace(): Boolean {
        val stat = StatFs(cacheDir.absolutePath)
        return stat.availableBytes >= MIN_FREE_BYTES
    }

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
