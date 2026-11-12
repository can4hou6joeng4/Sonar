package cn.bobochang.sonar.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject

val SonarJson: Json = Json {
    ignoreUnknownKeys = true
    encodeDefaults = true
    explicitNulls = false
    isLenient = true
}

@Serializable
enum class MusicSource(val displayName: String) {
    @SerialName("wy")
    WY("网易云"),

    @SerialName("tx")
    TX("QQ"),

    @SerialName("kg")
    KG("酷狗"),

    @SerialName("local")
    LOCAL("本地");

    val isEnabled: Boolean
        get() = this == LOCAL || this == WY

    companion object {
        fun fromWire(value: String?): MusicSource =
            entries.firstOrNull { it.wire == value } ?: WY
    }
}

@Serializable
enum class Quality(val rank: Int, val displayName: String) {
    @SerialName("128k")
    STANDARD(1, "标准"),

    @SerialName("320k")
    HIGH(2, "较高"),

    @SerialName("flac")
    LOSSLESS(3, "无损"),

    @SerialName("flac24bit")
    HI_RES(4, "Hi-Res"),

    @SerialName("master")
    MASTER(5, "母带");

    /** 实际音质不低于目标档位时返回 true。 */
    fun satisfies(target: Quality): Boolean = rank >= target.rank

    companion object {
        val descending: List<Quality> = entries.sortedByDescending { it.rank }

        fun fromWire(value: String?): Quality? = entries.firstOrNull { it.wireName() == value }

        fun fromNetEaseLevel(value: String?): Quality? = when (value?.lowercase()) {
            "vivid", "jymaster", "sky", "jyeffect" -> MASTER
            "hires" -> HI_RES
            "lossless" -> LOSSLESS
            "exhigh", "higher" -> HIGH
            "standard" -> STANDARD
            else -> null
        }

        fun fromBitrate(bitrate: Int?): Quality = when {
            bitrate == null -> STANDARD
            bitrate >= 2_000_000 -> MASTER
            bitrate >= 1_500_000 -> HI_RES
            bitrate >= 700_000 -> LOSSLESS
            bitrate >= 300_000 -> HIGH
            else -> STANDARD
        }

        private fun Quality.wireName(): String = when (this) {
            STANDARD -> "128k"
            HIGH -> "320k"
            LOSSLESS -> "flac"
            HI_RES -> "flac24bit"
            MASTER -> "master"
        }
    }
}

@Serializable
data class Track(
    val source: MusicSource,
    val songmid: String,
    val title: String,
    val artist: String,
    val album: String = "",
    val interval: String? = null,
    val payload: JsonObject = JsonObject(emptyMap()),
) {
    val musicId: String get() = "${source.wire}_$songmid"

    val coverUrl: String?
        get() = payload.string("picUrl")
            ?: payload.string("img")
            ?: payload.string("artworkUri")
            ?: payload.obj("al")?.string("picUrl")
            ?: payload.obj("album")?.string("picUrl")

    val durationMs: Long?
        get() = interval?.let(::parseIntervalMillis)

    val isPlayable: Boolean
        get() {
            val direct = payload.int("st")
            if (direct != null && direct < 0) return false
            val privilege = payload.obj("privilege") ?: return true
            val status = privilege.int("st") ?: privilege.int("status")
            return status == null || status >= 0
        }

    fun toJson(): String = SonarJson.encodeToString(Track.serializer(), this)

    companion object {
        fun fromJson(value: String): Track? = runCatching {
            SonarJson.decodeFromString(Track.serializer(), value)
        }.getOrNull()

        fun fromRaw(source: MusicSource, raw: JsonObject): Track? {
            val id = raw.string("songmid") ?: raw.string("id") ?: return null
            val title = raw.string("name") ?: return null
            val artist = raw.string("singer")
                ?: raw.string("artistName")
                ?: raw.arr("ar")?.firstOrNull()?.jsonObject?.string("name")
                ?: raw.arr("artists")?.firstOrNull()?.jsonObject?.string("name")
                ?: return null
            val album = raw.string("albumName")
                ?: raw.obj("al")?.string("name")
                ?: raw.obj("album")?.string("name")
                ?: ""
            return Track(
                source = source,
                songmid = id,
                title = title,
                artist = artist,
                album = album,
                interval = raw.string("interval"),
                payload = raw,
            )
        }
    }
}

val MusicSource.wire: String
    get() = when (this) {
        MusicSource.WY -> "wy"
        MusicSource.TX -> "tx"
        MusicSource.KG -> "kg"
        MusicSource.LOCAL -> "local"
    }

val Quality.wire: String
    get() = when (this) {
        Quality.STANDARD -> "128k"
        Quality.HIGH -> "320k"
        Quality.LOSSLESS -> "flac"
        Quality.HI_RES -> "flac24bit"
        Quality.MASTER -> "master"
    }

val Quality.title: String
    get() = when (this) {
        Quality.MASTER -> "最高音质优先"
        Quality.HI_RES -> "Hi-Res"
        Quality.LOSSLESS -> "无损 FLAC"
        Quality.HIGH -> "高品质 320K"
        Quality.STANDARD -> "标准品质 128K"
    }

val Quality.badgeTitle: String
    get() = when (this) {
        Quality.MASTER -> "母带"
        Quality.HI_RES -> "Hi-Res"
        Quality.LOSSLESS -> "无损"
        Quality.HIGH -> "320K"
        Quality.STANDARD -> "128K"
    }

/** 与 iOS `Track.highestKnownQuality` 对齐：只依赖曲目元数据里声明的可播档位。 */
val Track.highestKnownQuality: Quality
    get() {
        val types = payload.arr("types") ?: return Quality.STANDARD
        val values = types.mapNotNull { (it as? JsonObject)?.string("type") }.toSet()
        return when {
            "master" in values -> Quality.MASTER
            "flac24bit" in values -> Quality.HI_RES
            "flac" in values -> Quality.LOSSLESS
            "320k" in values -> Quality.HIGH
            else -> Quality.STANDARD
        }
    }

data class TrackQualityOption(val quality: Quality, val sizeText: String) {
    companion object {
        fun available(track: Track): List<TrackQualityOption> {
            val types = track.payload.arr("types") ?: return emptyList()
            val values = types.mapNotNull { element ->
                val obj = element as? JsonObject ?: return@mapNotNull null
                val quality = Quality.fromWire(obj.string("type")) ?: return@mapNotNull null
                TrackQualityOption(quality, obj.string("size").orEmpty())
            }
            return Quality.descending.mapNotNull { quality ->
                values.firstOrNull { it.quality == quality }
            }
        }
    }
}

@Serializable
data class ArtistSummary(
    val id: String,
    val source: MusicSource,
    val name: String,
    val imageUrl: String? = null,
    val songCount: Int? = null,
    val albumCount: Int? = null,
) {
    val stableId: String get() = "${source.wire}_artist_$id"
}

@Serializable
data class AlbumSummary(
    val id: String,
    val source: MusicSource,
    val name: String,
    val artist: String = "",
    val imageUrl: String? = null,
    val releaseDate: String? = null,
    val trackCount: Int? = null,
) {
    val stableId: String get() = "${source.wire}_album_$id"
}

@Serializable
data class PlaylistSummary(
    val id: String,
    val name: String,
    val imageUrl: String? = null,
    val author: String = "",
    val playCount: String = "",
    val total: Int? = null,
    val description: String? = null,
    val source: MusicSource = MusicSource.WY,
) {
    val key: String get() = "${source.wire}:$id"
}

@Serializable
data class SearchPage(
    val items: List<Track>,
    val total: Int,
    val page: Int = 1,
    val limit: Int = 25,
) {
    val hasMore: Boolean get() = page * limit < total
}

@Serializable
data class LyricInfo(
    val lyric: String = "",
    val translation: String? = null,
    val romanization: String? = null,
    val karaoke: String? = null,
)

internal fun JsonObject.string(key: String): String? =
    (this[key] as? JsonPrimitive)?.contentOrNull?.trim()?.takeIf { it.isNotEmpty() }

internal fun JsonObject.int(key: String): Int? =
    (this[key] as? JsonPrimitive)?.contentOrNull?.toIntOrNull()

internal fun JsonObject.long(key: String): Long? =
    (this[key] as? JsonPrimitive)?.contentOrNull?.toLongOrNull()

internal fun JsonObject.obj(key: String): JsonObject? =
    (this[key] as? JsonObject)

internal fun JsonObject.arr(key: String) =
    (this[key] as? kotlinx.serialization.json.JsonArray)

internal fun kotlinx.serialization.json.JsonElement.asString(): String? =
    (this as? JsonPrimitive)?.contentOrNull

internal fun kotlinx.serialization.json.JsonElement.asObject(): JsonObject? = this as? JsonObject

fun parseIntervalMillis(interval: String): Long? {
    val parts = interval.split(":").mapNotNull { it.toLongOrNull() }
    if (parts.isEmpty()) return null
    return parts.fold(0L) { acc, part -> acc * 60L + part } * 1000L
}

fun formatDurationMs(ms: Long): String {
    if (ms <= 0) return "0:00"
    val totalSeconds = ms / 1000
    val hours = totalSeconds / 3600
    val minutes = (totalSeconds % 3600) / 60
    val seconds = totalSeconds % 60
    return if (hours > 0) {
        "%d:%02d:%02d".format(hours, minutes, seconds)
    } else {
        "%d:%02d".format(minutes, seconds)
    }
}
