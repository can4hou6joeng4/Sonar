package cn.bobochang.sonar.data.net

import cn.bobochang.sonar.data.model.AlbumSummary
import cn.bobochang.sonar.data.model.ArtistSummary
import cn.bobochang.sonar.data.model.LyricInfo
import cn.bobochang.sonar.data.model.MusicSource
import cn.bobochang.sonar.data.model.PlaylistSummary
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
import cn.bobochang.sonar.data.model.wire
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.IOException
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/**
 * 网易云 legacy `/api/` 只读接口。只依赖登录 Cookie `MUSIC_U`，不需要 eapi 加密。
 */
class NetEaseWebClient(
    private val cookieProvider: () -> String?,
    private val client: OkHttpClient = SonarHttp.client,
) {
    data class NativePlayback(
        val url: String,
        val quality: Quality,
        val format: String?,
    )

    data class RemotePlaylist(
        val name: String,
        val tracks: List<Track>,
        val total: Int,
        val imageUrl: String?,
        val author: String,
        val description: String?,
        val playCount: String,
    )

    suspend fun account(): Pair<String, Int> {
        if (cookieProvider().isNullOrBlank()) {
            throw SourceException.CredentialRequired("还没有配置网易云登录 Cookie")
        }
        val obj = get("/api/nuser/account/get")
        val profile = obj.obj("profile")
            ?: throw SourceException.Message("账号信息缺失，请检查 Cookie 是否有效")
        val nickname = profile.string("nickname") ?: ""
        val vipType = obj.obj("account")?.int("vipType") ?: 0
        return nickname to vipType
    }

    suspend fun searchSongs(keyword: String, limit: Int = 25, offset: Int = 0): SearchPage {
        val obj = get(
            "/api/search/get",
            mapOf("s" to keyword, "type" to "1", "limit" to limit.toString(), "offset" to offset.toString()),
        )
        val result = obj.obj("result") ?: JsonObject(emptyMap())
        val songs = result.arr("songs") ?: JsonArray(emptyList())
        val tracks = songs.mapNotNull { it.asObject()?.let(::trackFrom) }
        if (songs.isNotEmpty() && tracks.isEmpty()) {
            throw SourceException.Message("搜索结果缺少曲目信息")
        }
        return SearchPage(
            items = tracks,
            total = result.int("songCount") ?: tracks.size,
            page = offset / limit.coerceAtLeast(1) + 1,
            limit = limit,
        )
    }

    suspend fun searchArtists(keyword: String, limit: Int = 20, offset: Int = 0): Pair<List<ArtistSummary>, Int> {
        val obj = get(
            "/api/search/get",
            mapOf("s" to keyword, "type" to "100", "limit" to limit.toString(), "offset" to offset.toString()),
        )
        val result = obj.obj("result") ?: JsonObject(emptyMap())
        val raw = result.arr("artists") ?: JsonArray(emptyList())
        val artists = raw.mapNotNull { it.asObject()?.let(::artistFrom) }
        return artists to (result.int("artistCount") ?: artists.size)
    }

    suspend fun searchAlbums(keyword: String, limit: Int = 20, offset: Int = 0): Pair<List<AlbumSummary>, Int> {
        val obj = get(
            "/api/search/get",
            mapOf("s" to keyword, "type" to "10", "limit" to limit.toString(), "offset" to offset.toString()),
        )
        val result = obj.obj("result") ?: JsonObject(emptyMap())
        val raw = result.arr("albums") ?: JsonArray(emptyList())
        val albums = raw.mapNotNull { it.asObject()?.let(::albumFrom) }
        return albums to (result.int("albumCount") ?: albums.size)
    }

    suspend fun searchPlaylists(keyword: String, limit: Int = 20, offset: Int = 0): Pair<List<PlaylistSummary>, Int> {
        val obj = get(
            "/api/search/get",
            mapOf("s" to keyword, "type" to "1000", "limit" to limit.toString(), "offset" to offset.toString()),
        )
        val result = obj.obj("result") ?: JsonObject(emptyMap())
        val raw = result.arr("playlists") ?: JsonArray(emptyList())
        val playlists = raw.mapNotNull { it.asObject()?.let(::playlistFrom) }
        return playlists to (result.int("playlistCount") ?: playlists.size)
    }

    suspend fun hotSearches(limit: Int = 12): List<String> {
        val obj = get("/api/search/hot", mapOf("type" to "1111"))
        val hots = obj.obj("result")?.arr("hots") ?: JsonArray(emptyList())
        return hots.mapNotNull { it.asObject()?.string("first")?.trim() }
            .filter { it.isNotEmpty() }
            .distinct()
            .take(limit)
    }

    suspend fun searchSuggestions(keyword: String, limit: Int = 8): List<String> {
        val obj = get("/api/search/suggest/keyword", mapOf("s" to keyword))
        val matches = obj.obj("result")?.arr("allMatch") ?: JsonArray(emptyList())
        return matches.mapNotNull { it.asObject()?.string("keyword")?.trim() }
            .filter { it.isNotEmpty() }
            .distinct()
            .take(limit)
    }

    suspend fun artist(id: String): Pair<ArtistSummary, List<Track>> {
        val obj = get("/api/v1/artist/$id")
        val artist = obj.obj("artist")?.let(::artistFrom)
            ?: throw SourceException.Message("歌手信息缺失")
        val tracks = obj.arr("hotSongs")?.mapNotNull { it.asObject()?.let(::trackFrom) } ?: emptyList()
        return artist to tracks
    }

    suspend fun artistAlbums(id: String, limit: Int = 24, offset: Int = 0): List<AlbumSummary> {
        val obj = get("/api/artist/albums/$id", mapOf("limit" to limit.toString(), "offset" to offset.toString()))
        return obj.arr("hotAlbums")?.mapNotNull { it.asObject()?.let(::albumFrom) } ?: emptyList()
    }

    suspend fun album(id: String): Pair<AlbumSummary, List<Track>> {
        val obj = get("/api/v1/album/$id")
        val album = obj.obj("album")?.let(::albumFrom)
            ?: throw SourceException.Message("专辑信息缺失")
        val tracks = obj.arr("songs")?.mapNotNull { it.asObject()?.let(::trackFrom) } ?: emptyList()
        return album to tracks
    }

    suspend fun songDetail(ids: List<String>): List<Track> {
        if (ids.isEmpty()) return emptyList()
        val obj = get("/api/song/detail", mapOf("ids" to ids.joinToString(",", prefix = "[", postfix = "]")))
        return obj.arr("songs")?.mapNotNull { it.asObject()?.let(::trackFrom) } ?: emptyList()
    }

    suspend fun lyric(id: String): LyricInfo {
        val obj = get(
            "/api/song/lyric",
            mapOf("id" to id, "lv" to "-1", "kv" to "-1", "tv" to "-1", "rv" to "-1"),
        )
        fun text(key: String): String? {
            val value = obj.obj(key)?.string("lyric") ?: return null
            return value.takeIf { it.isNotBlank() }
        }
        val lyric = text("lrc") ?: throw SourceException.Unavailable("歌词为空")
        return LyricInfo(
            lyric = lyric,
            translation = text("tlyric"),
            romanization = text("romalrc"),
            karaoke = text("klyric"),
        )
    }

    suspend fun playableUrl(id: String, quality: Quality): NativePlayback? {
        val level = when (quality) {
            Quality.STANDARD -> "standard"
            Quality.HIGH -> "exhigh"
            Quality.LOSSLESS -> "lossless"
            Quality.HI_RES -> "hires"
            Quality.MASTER -> "jymaster"
        }
        val encodeType = if (quality.rank >= Quality.LOSSLESS.rank) "flac" else "mp3"
        val obj = get(
            "/api/song/enhance/player/url/v1",
            mapOf("ids" to "[$id]", "level" to level, "encodeType" to encodeType),
        )
        val item = obj.arr("data")?.firstOrNull()?.asObject() ?: return null
        if (item["freeTrialInfo"] != null && item["freeTrialInfo"] !is JsonNull) {
            throw SourceException.TrialOnly()
        }
        val rawUrl = item.string("url") ?: return null
        val url = normalizeHttps(rawUrl) ?: return null
        val actual = Quality.fromNetEaseLevel(item.string("level")) ?: Quality.fromBitrate(item.int("br"))
        return NativePlayback(url, actual, item.string("type"))
    }

    suspend fun playlistDetail(id: String, limit: Int = 1000): RemotePlaylist {
        val obj = get("/api/v6/playlist/detail", mapOf("id" to id, "n" to limit.toString()))
        val raw = obj.obj("playlist") ?: throw SourceException.Message("歌单信息缺失")
        val name = raw.string("name") ?: throw SourceException.Message("歌单信息缺失")
        val tracks = raw.arr("tracks")?.mapNotNull { it.asObject()?.let(::trackFrom) } ?: emptyList()
        return RemotePlaylist(
            name = name,
            tracks = tracks,
            total = raw.int("trackCount") ?: tracks.size,
            imageUrl = (raw.string("coverImgUrl") ?: raw.string("img"))?.let(::normalizeHttps),
            author = raw.obj("creator")?.string("nickname") ?: "",
            description = raw.string("description"),
            playCount = raw.long("playCount")?.toString() ?: "",
        )
    }

    private suspend fun get(path: String, query: Map<String, String> = emptyMap()): JsonObject =
        withContext(Dispatchers.IO) {
            val builder = "https://music.163.com$path".toHttpUrl().newBuilder()
            query.forEach { (key, value) -> builder.addQueryParameter(key, value) }
            val url = builder.build()
            var last: Throwable? = null
            for (attempt in 0..1) {
                try {
                    val requestBuilder = Request.Builder()
                        .url(url)
                        .header("User-Agent", USER_AGENT)
                        .header("Referer", "https://music.163.com/")
                        .header("Accept", "application/json")
                    cookieProvider()?.takeIf { it.isNotBlank() }?.let {
                        requestBuilder.header("Cookie", "MUSIC_U=$it; os=ios; appver=9.6.07")
                    }
                    client.newCall(requestBuilder.build()).execute().use { response ->
                        if (!response.isSuccessful) {
                            throw SourceException.Message("网易云接口返回 HTTP ${response.code}")
                        }
                        val body = response.body?.string()
                            ?: throw SourceException.Message("网易云接口返回空数据")
                        val obj = SonarJson.parseToJsonElement(body).jsonObject
                        val code = obj.int("code") ?: 200
                        if (code != 200) {
                            val message = obj.string("message") ?: obj.string("msg") ?: ""
                            throw SourceException.Message(
                                "网易云接口错误 $code" + if (message.isBlank()) "" else "：$message",
                            )
                        }
                        return@withContext obj
                    }
                } catch (error: CancellationException) {
                    throw error
                } catch (error: SourceException) {
                    throw error
                } catch (error: Throwable) {
                    last = error
                    if (attempt == 0) delay(350)
                }
            }
            throw (last ?: IOException("请求失败")).toSourceException()
        }

    private fun trackFrom(raw: JsonObject): Track? {
        val songmid = raw.long("id")?.toString() ?: raw.string("id") ?: return null
        val title = raw.string("name") ?: return null
        val artistArray = raw.arr("ar") ?: raw.arr("artists")
        val artists = artistArray?.mapNotNull { it.asObject()?.string("name") } ?: emptyList()
        val album = raw.obj("al") ?: raw.obj("album") ?: JsonObject(emptyMap())
        val interval = (raw.long("dt") ?: raw.long("duration"))?.let(::formatInterval)
        val payload = buildJsonObject {
            put("songmid", songmid)
            put("name", title)
            put("singer", artists.joinToString("/"))
            put("albumName", album.string("name") ?: "")
            (album.string("picUrl") ?: raw.string("picUrl"))?.let { put("picUrl", it) }
            album.long("id")?.let { put("albumID", it) }
            artistArray?.firstOrNull()?.asObject()?.let { first ->
                first.long("id")?.let { put("artistID", it) }
                first.string("name")?.let { put("artistName", it) }
            }
            interval?.let { put("interval", it) }
            put("types", qualityTypes(raw))
            raw.int("st")?.let { put("st", it) }
            raw.int("fee")?.let { put("fee", it) }
            raw.obj("privilege")?.let { put("privilege", it) }
        }
        return Track(
            source = MusicSource.WY,
            songmid = songmid,
            title = title,
            artist = artists.joinToString("/"),
            album = album.string("name") ?: "",
            interval = interval,
            payload = payload,
        )
    }

    private fun qualityTypes(raw: JsonObject): JsonArray = buildJsonArray {
        fun append(key: String, quality: Quality) {
            val entry = raw.obj(key) ?: return
            val size = entry.long("size") ?: entry.long("filesize") ?: return
            if (size <= 0) return
            add(buildJsonObject {
                put("type", quality.wire)
                put("size", size.toString())
            })
        }
        append("l", Quality.STANDARD)
        append("h", Quality.HIGH)
        append("sq", Quality.LOSSLESS)
        append("hr", Quality.HI_RES)
    }

    private fun artistFrom(raw: JsonObject): ArtistSummary? {
        val id = (raw.long("id") ?: raw.long("artistId"))?.toString() ?: raw.string("id") ?: return null
        val name = raw.string("name") ?: return null
        return ArtistSummary(
            id = id,
            source = MusicSource.WY,
            name = name,
            imageUrl = (raw.string("picUrl") ?: raw.string("img1v1Url"))?.let(::normalizeHttps),
            songCount = raw.int("musicSize") ?: raw.int("songSize"),
            albumCount = raw.int("albumSize"),
        )
    }

    private fun albumFrom(raw: JsonObject): AlbumSummary? {
        val id = raw.long("id")?.toString() ?: raw.string("id") ?: return null
        val name = raw.string("name") ?: return null
        val artist = raw.obj("artist")?.string("name")
            ?: raw.arr("artists")?.firstOrNull()?.asObject()?.string("name")
            ?: ""
        val release = raw.long("publishTime")?.let {
            DateTimeFormatter.ofPattern("yyyy-MM-dd")
                .withZone(ZoneOffset.UTC)
                .format(Instant.ofEpochMilli(it))
        }
        return AlbumSummary(
            id = id,
            source = MusicSource.WY,
            name = name,
            artist = artist,
            imageUrl = (raw.string("picUrl") ?: raw.string("blurPicUrl"))?.let(::normalizeHttps),
            releaseDate = release,
            trackCount = raw.int("size") ?: raw.int("trackCount"),
        )
    }

    private fun playlistFrom(raw: JsonObject): PlaylistSummary? {
        val id = raw.long("id")?.toString() ?: raw.string("id") ?: return null
        val name = raw.string("name") ?: return null
        return PlaylistSummary(
            id = id,
            name = name,
            imageUrl = (raw.string("coverImgUrl") ?: raw.string("img"))?.let(::normalizeHttps),
            author = raw.obj("creator")?.string("nickname") ?: "",
            playCount = raw.long("playCount")?.toString() ?: "",
            total = raw.int("trackCount"),
            description = raw.string("description"),
            source = MusicSource.WY,
        )
    }

    companion object {
        private const val USER_AGENT = "neteasemusic/9.6.07 (iPhone; iOS 27.0.1; Scale/3.00)"

        fun normalizeCookie(raw: String?): String? {
            val trimmed = raw?.trim().orEmpty()
            if (trimmed.isEmpty()) return null
            val marker = "MUSIC_U="
            val index = trimmed.indexOf(marker)
            if (index >= 0) {
                val rest = trimmed.substring(index + marker.length)
                val value = rest.substringBefore(';').trim()
                return value.takeIf { it.isNotEmpty() }
            }
            return trimmed
        }

        private fun formatInterval(milliseconds: Long): String {
            val seconds = (milliseconds / 1000).coerceAtLeast(0)
            return "%02d:%02d".format(seconds / 60, seconds % 60)
        }
    }
}
