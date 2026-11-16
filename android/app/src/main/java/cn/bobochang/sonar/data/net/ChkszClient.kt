package cn.bobochang.sonar.data.net

import cn.bobochang.sonar.data.model.LyricInfo
import cn.bobochang.sonar.data.model.MusicSource
import cn.bobochang.sonar.data.model.Quality
import cn.bobochang.sonar.data.model.SearchPage
import cn.bobochang.sonar.data.model.SonarJson
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.data.model.arr
import cn.bobochang.sonar.data.model.asObject
import cn.bobochang.sonar.data.model.int
import cn.bobochang.sonar.data.model.long
import cn.bobochang.sonar.data.model.obj
import cn.bobochang.sonar.data.model.string
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.IOException

/**
 * ChKSz 第三方音源。凭据只来自用户设置或构建期注入，不写入日志。
 */
class ChkszClient(
    private val keyProvider: () -> String?,
    private val client: OkHttpClient = SonarHttp.client,
) {
    data class RemotePlayback(
        val url: String,
        val quality: Quality,
    )

    private var disabled: String? = null
    private var rateLimitedUntil: Long = 0L

    val hasKey: Boolean
        get() = !keyProvider().isNullOrBlank()

    suspend fun search(keyword: String, page: Int = 1, limit: Int = 25): SearchPage {
        val safePage = page.coerceAtLeast(1)
        val safeLimit = limit.coerceIn(1, 100)
        val obj = request(
            "/api/163_search",
            mapOf(
                "keyword" to keyword,
                "limit" to safeLimit.toString(),
                "offset" to ((safePage - 1) * safeLimit).toString(),
            ),
        )
        val payload = obj["data"]
        val songs: JsonArray
        val total: Int
        if (payload is JsonObject) {
            songs = payload.arr("songs") ?: JsonArray(emptyList())
            total = payload.int("total") ?: songs.size
        } else if (payload is JsonArray) {
            songs = payload
            total = songs.size
        } else {
            throw SourceException.Message("ChKSz 网易搜索返回数据异常")
        }
        val tracks = songs.mapNotNull { it.asObject()?.let(::trackFrom) }
        if (songs.isNotEmpty() && tracks.isEmpty()) {
            throw SourceException.Message("ChKSz 网易搜索结果缺少曲目信息")
        }
        return SearchPage(tracks, total, safePage, safeLimit)
    }

    suspend fun lyric(track: Track): LyricInfo {
        requireTrack(track)
        val obj = request("/api/163_lyric", mapOf("id" to track.songmid))
        val payload = obj.obj("data")
            ?: throw SourceException.Message("ChKSz 网易歌词返回数据异常")
        val lyric = payload.string("lrc")
            ?: throw SourceException.Message("ChKSz 网易歌词返回数据异常")
        return LyricInfo(
            lyric = lyric,
            translation = payload.string("tlyric"),
            romanization = payload.string("romalrc"),
            karaoke = payload.string("klyric"),
        )
    }

    suspend fun musicUrl(track: Track, quality: Quality): RemotePlayback {
        requireTrack(track)
        val level = when (quality) {
            Quality.STANDARD -> "standard"
            Quality.HIGH -> "exhigh"
            Quality.LOSSLESS -> "lossless"
            Quality.HI_RES -> "hires"
            Quality.MASTER -> "jymaster"
        }
        val obj = request(
            "/api/163_music",
            mapOf("id" to track.songmid, "level" to level, "type" to "json"),
        )
        val payload = obj.obj("data")
            ?: throw SourceException.Message("ChKSz 网易播放未返回可用链接")
        val rawUrl = payload.string("url")
            ?: throw SourceException.Message("ChKSz 网易播放未返回可用链接")
        val url = normalizeHttps(rawUrl)
            ?: throw SourceException.Message("ChKSz 播放链接无效")
        val actual = qualityFrom(payload.string("level"), payload.int("br"))
        return RemotePlayback(url, actual)
    }

    private suspend fun request(path: String, parameters: Map<String, String>): JsonObject =
        withContext(Dispatchers.IO) {
            val key = keyProvider()?.trim()
            if (key.isNullOrEmpty()) {
                throw SourceException.CredentialRequired("未配置 ChKSz 凭据，第三方音源暂不可用")
            }
            disabled?.let { throw SourceException.Message("ChKSz 已停用（$it）") }
            val now = System.currentTimeMillis()
            if (rateLimitedUntil > now) {
                throw SourceException.Message("ChKSz 限流冷却中（HTTP 429）")
            }

            val urlBuilder = "https://api.chksz.com$path".toHttpUrl().newBuilder()
            (parameters + ("apikey" to key))
                .toSortedMap()
                .forEach { (name, value) -> urlBuilder.addQueryParameter(name, value) }
            val url = urlBuilder.build()

            var last: Throwable? = null
            for (attempt in 0..1) {
                try {
                    val request = Request.Builder().url(url).get().build()
                    val (response, responseBody) = client.newCall(request).awaitResponse {
                        it to it.body?.string()
                    }
                    run {
                        if (response.code == 429 && attempt == 0) {
                            val retryAfter = response.header("Retry-After")?.toLongOrNull() ?: 5L
                            if (retryAfter in 0..10) {
                                delay(retryAfter * 1000)
                                return@run
                            }
                        }
                        when (response.code) {
                            200 -> Unit
                            401, 403 -> {
                                disable("HTTP ${response.code}")
                                throw SourceException.CredentialRequired("ChKSz 凭证无效或已过期（HTTP ${response.code}）")
                            }
                            402 -> {
                                disable("HTTP 402")
                                throw SourceException.CredentialRequired("ChKSz 额度已耗尽（HTTP 402）")
                            }
                            429 -> {
                                rateLimitedUntil = System.currentTimeMillis() + 5_000
                                throw SourceException.Message("ChKSz 请求过于频繁（HTTP 429）")
                            }
                            else -> throw SourceException.Message("第三方请求失败（HTTP ${response.code}）")
                        }
                        val body = responseBody
                            ?: throw SourceException.Message("ChKSz 返回空数据")
                        val obj = SonarJson.parseToJsonElement(body).jsonObject
                        val code = obj.int("code")
                        if (code != null && code != 200) {
                            when (code) {
                                401, 403 -> {
                                    disable("API $code")
                                    throw SourceException.CredentialRequired("ChKSz 凭证无效或已过期（API $code）")
                                }
                                402 -> {
                                    disable("API 402")
                                    throw SourceException.CredentialRequired("ChKSz 额度已耗尽（API 402）")
                                }
                                429 -> {
                                    rateLimitedUntil = System.currentTimeMillis() + 5_000
                                    throw SourceException.Message("ChKSz 请求过于频繁（API 429）")
                                }
                                else -> {
                                    val detail = obj.string("msg") ?: "返回异常（API $code）"
                                    throw SourceException.Message(
                                        if (detail.lowercase().contains("chksz")) detail else "ChKSz: $detail",
                                    )
                                }
                            }
                        }
                        return@withContext obj
                    }
                    if (attempt == 0) continue
                } catch (error: CancellationException) {
                    throw error
                } catch (error: SourceException) {
                    throw error
                } catch (error: Throwable) {
                    last = error
                    if (attempt == 0) delay(250)
                }
            }
            throw (last ?: IOException("ChKSz 请求失败")).toSourceException()
        }

    @Synchronized
    private fun disable(reason: String) {
        disabled = reason
    }

    /** 用户更新 Key 后允许重新尝试，避免一次失败在进程生命周期内永久停用。 */
    @Synchronized
    fun resetCircuit() {
        disabled = null
        rateLimitedUntil = 0L
    }

    private fun requireTrack(track: Track) {
        if (track.source != MusicSource.WY || track.songmid.toLongOrNull()?.let { it > 0 } != true) {
            throw SourceException.Message("网易云歌曲标识无效")
        }
    }

    private fun trackFrom(song: JsonObject): Track? {
        val id = song.long("id")?.toString() ?: song.string("id") ?: return null
        if (id.toLongOrNull()?.let { it > 0 } != true) return null
        val name = song.string("name") ?: return null
        val artist = when (val value = song["artists"]) {
            is JsonArray -> value.mapNotNull { element ->
                when (element) {
                    is JsonObject -> element.string("name")
                    is JsonPrimitive -> element.content
                    else -> null
                }
            }.joinToString("、")
            else -> song.string("artists") ?: song.string("artist") ?: ""
        }.takeIf { it.isNotBlank() } ?: return null
        val album = song.string("album") ?: ""
        val interval = song.long("duration")?.takeIf { it > 0 }?.let {
            val seconds = it / 1000
            "%d:%02d".format(seconds / 60, seconds % 60)
        }
        val payload = buildJsonObject {
            put("songmid", id)
            put("name", name)
            put("singer", artist)
            put("albumName", album)
            interval?.let { put("interval", it) }
            song.string("picUrl")?.let { normalizeHttps(it)?.let { url -> put("picUrl", url) } }
        }
        return Track(
            source = MusicSource.WY,
            songmid = id,
            title = name,
            artist = artist,
            album = album,
            interval = interval,
            payload = payload,
        )
    }

    companion object {
        fun qualityFrom(level: String?, bitrate: Int?): Quality = when (level?.lowercase()) {
            "standard" -> Quality.STANDARD
            "exhigh", "higher" -> Quality.HIGH
            "lossless" -> Quality.LOSSLESS
            "hires", "sky", "jyeffect" -> Quality.HI_RES
            "jymaster", "vivid", "master" -> Quality.MASTER
            else -> Quality.fromBitrate(bitrate)
        }
    }
}
