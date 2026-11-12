package cn.bobochang.sonar.data.library

import cn.bobochang.sonar.data.model.MusicSource
import cn.bobochang.sonar.data.model.Quality
import cn.bobochang.sonar.data.model.SonarJson
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.data.model.wire
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

/**
 * 与 iOS 端 `sonar.personal-playlist` v1 互通的纯元数据备份。
 */
object PlaylistBackupCodec {
    const val MAX_BYTES = 10 * 1024 * 1024
    private const val MAX_TRACKS = 50_000
    private const val FORMAT = "sonar.personal-playlist"

    data class Imported(val name: String, val tracks: List<Track>)

    @Serializable
    private data class Document(
        val format: String = FORMAT,
        val version: Int = 1,
        val name: String,
        val tracks: List<Entry>,
    )

    @Serializable
    private data class Entry(
        val source: String,
        val songmid: String,
        val title: String,
        val artist: String,
        val album: String = "",
        val interval: String? = null,
        val metadata: Metadata = Metadata(),
    )

    @Serializable
    private data class Metadata(
        val strMediaMid: String? = null,
        val songId: JsonElement? = null,
        val albumId: JsonElement? = null,
        val albumMid: String? = null,
        val img: String? = null,
        val types: List<QualityDescriptor>? = null,
        @SerialName("_types") val legacyTypes: Map<String, QualitySize>? = null,
    )

    @Serializable
    private data class QualityDescriptor(val type: String, val size: String? = null)

    @Serializable
    private data class QualitySize(val size: String? = null)

    fun encode(name: String, tracks: List<Track>): String {
        // 本地文件的 SAF URI 不可跨设备迁移，备份只保留在线歌曲的元数据。
        val entries = tracks.filter { it.source != MusicSource.LOCAL }.map { track ->
            validateIdentifier(track.songmid, allowEmpty = false)
            val raw = track.payload
            val types = raw["types"]?.let { element ->
                runCatching {
                    SonarJson.decodeFromJsonElement(
                        kotlinx.serialization.builtins.ListSerializer(QualityDescriptor.serializer()),
                        element,
                    )
                }.getOrNull()
            }?.filter { Quality.fromWire(it.type) != null }
            val legacyTypes = raw["_types"]?.let { element ->
                runCatching {
                    SonarJson.decodeFromJsonElement(
                        kotlinx.serialization.builtins.MapSerializer(
                            String.serializer(),
                            QualitySize.serializer(),
                        ),
                        element,
                    )
                }.getOrNull()
            }?.filterKeys { Quality.fromWire(it) != null }
            Entry(
                source = track.source.wire,
                songmid = track.songmid,
                title = track.title,
                artist = track.artist,
                album = track.album,
                interval = track.interval,
                metadata = Metadata(
                    strMediaMid = raw["strMediaMid"]?.jsonPrimitive?.content,
                    songId = raw["songId"],
                    albumId = raw["albumId"],
                    albumMid = raw["albumMid"]?.jsonPrimitive?.content,
                    img = cleanArtwork(track.coverUrl),
                    types = types,
                    legacyTypes = legacyTypes?.takeIf { it.isNotEmpty() },
                ),
            )
        }
        val document = Document(name = name, tracks = entries)
        check(document.name.isNotBlank() && document.name.length <= 512)
        check(document.tracks.size <= MAX_TRACKS)
        val encoded = SonarJson.encodeToString(Document.serializer(), document)
        check(encoded.toByteArray().size <= MAX_BYTES)
        return encoded
    }

    fun decode(bytes: ByteArray): Imported {
        require(bytes.size <= MAX_BYTES) { "备份文件超过 10 MB" }
        val document = runCatching {
            SonarJson.decodeFromString(Document.serializer(), bytes.toString(Charsets.UTF_8))
        }.getOrElse { throw IllegalArgumentException("无法读取 Sonar 歌单备份") }
        require(document.format == FORMAT) { "不是 Sonar 导出的歌单备份" }
        require(document.version == 1) { "暂不支持此备份版本" }
        require(document.name.isNotBlank() && document.name.length <= 512) { "备份名称无效" }
        require(document.tracks.size <= MAX_TRACKS) { "备份歌曲数量过多" }
        val tracks = document.tracks.map { entry ->
            validateEntry(entry)
        }
        return Imported(document.name.trim(), tracks)
    }

    private fun validateEntry(entry: Entry): Track {
        validateIdentifier(entry.songmid, allowEmpty = false)
        require(entry.title.isNotBlank() && entry.title.length <= 2048) { "歌曲标题无效" }
        require(entry.artist.length <= 2048 && entry.album.length <= 2048) { "歌曲信息过长" }
        require((entry.interval?.length ?: 0) <= 32) { "歌曲时长无效" }
        if (!entry.interval.isNullOrBlank()) {
            val parts = entry.interval.split(':')
            require(parts.size in 1..3 && parts.all { part -> part.isNotEmpty() && part.all(Char::isDigit) }) {
                "歌曲时长格式无效"
            }
        }
        val source = MusicSource.entries.firstOrNull { it.wire == entry.source }
            ?: throw IllegalArgumentException("备份中包含不支持的音源：${entry.source}")
        val metadata = entry.metadata
        metadata.strMediaMid?.let { validateIdentifier(it, allowEmpty = true) }
        metadata.albumMid?.let { validateIdentifier(it, allowEmpty = true) }
        validateJsonIdentifier(metadata.songId)
        validateJsonIdentifier(metadata.albumId)
        metadata.types?.forEach { descriptor ->
            require(Quality.fromWire(descriptor.type) != null) { "备份中包含未知音质" }
            require((descriptor.size?.length ?: 0) <= 64) { "音质信息无效" }
        }
        metadata.legacyTypes?.forEach { (type, value) ->
            require(Quality.fromWire(type) != null) { "备份中包含未知音质" }
            require((value.size?.length ?: 0) <= 64) { "音质信息无效" }
        }
        val payload = buildJsonObject {
            put("songmid", entry.songmid)
            put("name", entry.title)
            put("singer", entry.artist)
            put("albumName", entry.album)
            entry.interval?.let { put("interval", it) }
            metadata.strMediaMid?.let { put("strMediaMid", it) }
            metadata.songId?.let { put("songId", it) }
            metadata.albumId?.let { put("albumId", it) }
            metadata.albumMid?.let { put("albumMid", it) }
            cleanArtwork(metadata.img)?.let { put("img", it) }
            metadata.types?.let { list ->
                put(
                    "types",
                    SonarJson.encodeToJsonElement(
                        kotlinx.serialization.builtins.ListSerializer(QualityDescriptor.serializer()),
                        list,
                    ),
                )
            }
            metadata.legacyTypes?.let { map ->
                put(
                    "_types",
                    SonarJson.encodeToJsonElement(
                        kotlinx.serialization.builtins.MapSerializer(
                            String.serializer(),
                            QualitySize.serializer(),
                        ),
                        map,
                    ),
                )
            }
        }
        return Track(
            source = source,
            songmid = entry.songmid,
            title = entry.title,
            artist = entry.artist,
            album = entry.album,
            interval = entry.interval,
            payload = payload,
        )
    }

    private fun cleanArtwork(value: String?): String? {
        val trimmed = value?.trim()?.takeIf { it.isNotEmpty() } ?: return null
        if (trimmed.length > 4096) return null
        val url = trimmed.toHttpUrlOrNull() ?: return null
        if (url.username.isNotEmpty() || url.password.isNotEmpty()) return null
        return url.newBuilder()
            .scheme("https")
            .query(null)
            .fragment(null)
            .build()
            .toString()
    }

    private fun validateIdentifier(value: String, allowEmpty: Boolean) {
        require(value.length <= 256 && (allowEmpty || value.isNotEmpty())) { "歌曲标识无效" }
        require(value.all { it.isLetterOrDigit() || it == '_' || it == '-' }) { "歌曲标识无效" }
    }

    private fun validateJsonIdentifier(value: JsonElement?) {
        if (value == null) return
        val primitive = value as? JsonPrimitive ?: throw IllegalArgumentException("歌曲标识无效")
        if (primitive.isString) {
            validateIdentifier(primitive.content, allowEmpty = true)
        } else {
            val number = primitive.content.toLongOrNull()
                ?: throw IllegalArgumentException("歌曲标识无效")
            require(number >= 0) { "歌曲标识无效" }
        }
    }
}
