package cn.bobochang.sonar.data.library

import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.data.model.arr
import cn.bobochang.sonar.data.model.asObject
import cn.bobochang.sonar.data.model.asString
import cn.bobochang.sonar.data.model.string
import java.util.Locale

/** 添加时间来自收藏或歌单成员；远程预览不包含该字段。 */
data class PlaylistEntry(val track: Track, val addedAt: Long? = null)

enum class AddedPeriod(val label: String, val days: Int?) {
    ALL("全部", null), WEEK("近 7 天", 7), MONTH("近 30 天", 30), UNKNOWN("未记录时间", null),
}

enum class PlaylistOrder(val label: String, val needsDate: Boolean = false) {
    ORIGINAL("原有顺序"), NEWEST("最新添加", true), OLDEST("最早添加", true),
    ARTIST("按歌手"), TITLE("按歌名"),
}

data class PlaylistFilter(
    val artist: String? = null,
    val period: AddedPeriod = AddedPeriod.ALL,
    val order: PlaylistOrder = PlaylistOrder.ORIGINAL,
) {
    val isActive: Boolean get() = artist != null || period != AddedPeriod.ALL || order != PlaylistOrder.ORIGINAL

    fun apply(entries: List<PlaylistEntry>, now: Long = System.currentTimeMillis()): List<PlaylistEntry> {
        val since = period.days?.let { now - it * 86_400_000L }
        val filtered = entries.filter { entry ->
            (artist == null || artist in artistsOf(entry.track)) &&
                (if (period == AddedPeriod.UNKNOWN) entry.addedAt == null
                else since == null || entry.addedAt?.let { it in since..now } == true)
        }
        return when (order) {
            PlaylistOrder.ORIGINAL -> filtered
            PlaylistOrder.NEWEST -> filtered.sortedWith(compareBy<PlaylistEntry> { it.addedAt == null }.thenByDescending { it.addedAt })
            PlaylistOrder.OLDEST -> filtered.sortedWith(compareBy<PlaylistEntry> { it.addedAt == null }.thenBy { it.addedAt })
            PlaylistOrder.ARTIST -> filtered.sortedBy { it.track.artist.lowercase(Locale.ROOT) }
            PlaylistOrder.TITLE -> filtered.sortedBy { it.track.title.lowercase(Locale.ROOT) }
        }
    }
}

fun artistsOf(track: Track): List<String> {
    val artists = (track.payload.arr("ar") ?: track.payload.arr("artists"))?.mapNotNull {
        it.asObject()?.string("name") ?: it.asString()
    }?.filter(String::isNotBlank)
    return artists?.takeIf { it.isNotEmpty() }?.distinct() ?: track.artist.split(Regex("[/、;；]"))
        .map(String::trim).filter(String::isNotEmpty).distinct().ifEmpty { listOf("未知歌手") }
}

fun playlistArtists(entries: List<PlaylistEntry>): List<String> = entries.flatMap { artistsOf(it.track) }
    .distinct().sortedBy { it.lowercase(Locale.ROOT) }
