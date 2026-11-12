package cn.bobochang.sonar.lyrics

import cn.bobochang.sonar.data.model.LyricInfo

data class LyricLine(
    val timeMs: Long,
    val text: String,
    val translation: String? = null,
    val romanization: String? = null,
)

object LrcParser {
    private val timeTag = Regex("""\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?]""")
    private val karaokeTag = Regex("""<\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?>|<\d+,\d+>""")

    private data class RawLine(val timeMs: Long, val text: String)

    fun parse(info: LyricInfo): List<LyricLine> {
        val raw = parseRaw(info.lyric)
        if (raw.isEmpty()) return emptyList()
        val translations = parseRaw(info.translation.orEmpty())
        val romanizations = parseRaw(info.romanization.orEmpty())
        return raw.map { line ->
            LyricLine(
                timeMs = line.timeMs,
                text = line.text,
                translation = nearest(translations, line.timeMs),
                romanization = nearest(romanizations, line.timeMs),
            )
        }.sortedBy { it.timeMs }
    }

    fun indexForTime(lines: List<LyricLine>, positionMs: Long): Int {
        if (lines.isEmpty()) return -1
        var low = 0
        var high = lines.lastIndex
        var result = -1
        while (low <= high) {
            val mid = (low + high) ushr 1
            if (lines[mid].timeMs <= positionMs) {
                result = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return result
    }

    private fun parseRaw(text: String): List<RawLine> {
        if (text.isBlank()) return emptyList()
        val result = mutableListOf<RawLine>()
        text.lineSequence().forEach { line ->
            val matches = timeTag.findAll(line).toList()
            if (matches.isEmpty()) return@forEach
            var content = line.substring(matches.last().range.last + 1).trim()
            if (content.isEmpty()) return@forEach
            content = karaokeTag.replace(content, "")
            if (content.isEmpty()) return@forEach
            matches.forEach { match ->
                val minutes = match.groupValues[1].toLongOrNull() ?: return@forEach
                val seconds = match.groupValues[2].toLongOrNull() ?: return@forEach
                val fraction = match.groupValues[3]
                val millis = when (fraction.length) {
                    0 -> 0L
                    1 -> fraction.toLong() * 100
                    2 -> fraction.toLong() * 10
                    else -> fraction.take(3).toLong()
                }
                result += RawLine((minutes * 60 + seconds) * 1000 + millis, content)
            }
        }
        return result
    }

    private fun nearest(lines: List<RawLine>, timeMs: Long): String? {
        if (lines.isEmpty()) return null
        var best: RawLine? = null
        var bestDistance = Long.MAX_VALUE
        for (line in lines) {
            val distance = kotlin.math.abs(line.timeMs - timeMs)
            if (distance < bestDistance) {
                bestDistance = distance
                best = line
            }
        }
        return best?.text?.takeIf { bestDistance <= 120 }
    }
}
