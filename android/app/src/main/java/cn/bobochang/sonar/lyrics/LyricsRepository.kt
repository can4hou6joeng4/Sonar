package cn.bobochang.sonar.lyrics

import android.content.Context
import android.net.Uri
import cn.bobochang.sonar.data.model.LyricInfo
import cn.bobochang.sonar.data.model.MusicSource
import cn.bobochang.sonar.data.model.SonarJson
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.data.model.string
import cn.bobochang.sonar.data.net.ChkszClient
import cn.bobochang.sonar.data.net.NetEaseWebClient
import cn.bobochang.sonar.data.net.SourceException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import java.io.File
import java.security.MessageDigest

class LyricsRepository(
    private val context: Context,
    private val netEase: NetEaseWebClient,
    private val chksz: ChkszClient,
) {
    @Serializable
    private data class CachedLyric(val info: LyricInfo, val savedAt: Long)

    private val cacheDir = File(context.cacheDir, "lyrics").apply { mkdirs() }
    private val memory = mutableMapOf<String, LyricInfo>()

    suspend fun load(track: Track): LyricInfo = withContext(Dispatchers.IO) {
        memory[track.musicId]?.let { return@withContext it }
        if (track.source == MusicSource.LOCAL) {
            val local = readLocal(track)
            memory[track.musicId] = local
            return@withContext local
        }

        val cacheFile = File(cacheDir, "${hash(track.musicId)}.json")
        val stale = readCache(cacheFile)
        if (stale != null && System.currentTimeMillis() - stale.savedAt < CACHE_TTL_MS) {
            memory[track.musicId] = stale.info
            return@withContext stale.info
        }

        val fetched = runCatching { netEase.lyric(track.songmid) }
            .recoverCatching {
                if (chksz.hasKey) chksz.lyric(track)
                else throw SourceException.Unavailable("歌词暂不可用")
            }
            .getOrElse { error ->
                stale?.info ?: throw (error as? SourceException
                    ?: SourceException.Message(error.message ?: "歌词加载失败"))
            }
        memory[track.musicId] = fetched
        writeCache(cacheFile, CachedLyric(fetched, System.currentTimeMillis()))
        fetched
    }

    fun parse(track: Track, info: LyricInfo): List<LyricLine> {
        val offset = 0L
        return LrcParser.parse(info).map { it.copy(timeMs = (it.timeMs + offset).coerceAtLeast(0)) }
    }

    fun parseKaraoke(info: LyricInfo): KaraokeLyrics = KaraokeLyrics(info)

    private fun readLocal(track: Track): LyricInfo {
        val lrcUri = track.payload.string("lrcUri")
        if (!lrcUri.isNullOrBlank()) {
            runCatching {
                context.contentResolver.openInputStream(Uri.parse(lrcUri))?.bufferedReader()?.use { it.readText() }
            }.getOrNull()?.takeIf { it.isNotBlank() }?.let { return LyricInfo(lyric = it) }
        }
        val path = track.payload.string("filePath") ?: track.songmid
        val audio = File(path)
        val sibling = File(audio.parentFile, audio.nameWithoutExtension + ".lrc")
        if (sibling.exists()) {
            runCatching { sibling.readText() }.getOrNull()?.takeIf { it.isNotBlank() }
                ?.let { return LyricInfo(lyric = it) }
        }
        return LyricInfo()
    }

    private fun readCache(file: File): CachedLyric? {
        if (!file.exists()) return null
        return runCatching {
            SonarJson.decodeFromString(CachedLyric.serializer(), file.readText())
        }.getOrNull()
    }

    private fun writeCache(file: File, value: CachedLyric) {
        runCatching {
            file.writeText(SonarJson.encodeToString(CachedLyric.serializer(), value))
        }
    }

    private fun hash(value: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(value.toByteArray())
        return digest.joinToString("") { "%02x".format(it) }
    }

    private companion object {
        const val CACHE_TTL_MS = 30L * 24 * 60 * 60 * 1000
    }
}
