package cn.bobochang.sonar.lyrics

import cn.bobochang.sonar.data.model.LyricInfo
import kotlin.math.abs
import kotlin.math.max

data class KaraokeToken(
    val id: Int,
    val text: String,
    val startMs: Int,
    val endMs: Int,
) {
    fun progress(atMilliseconds: Double): Double = when {
        atMilliseconds <= startMs -> 0.0
        atMilliseconds >= endMs -> 1.0
        else -> (atMilliseconds - startMs) / max(1, endMs - startMs).toDouble()
    }
}

data class KaraokeLine(
    val id: Int,
    val startMs: Int,
    val endMs: Int,
    val text: String,
    val translation: String? = null,
    val romanization: String? = null,
    val tokens: List<KaraokeToken> = emptyList(),
)

/**
 * 逐字歌词：优先解析网易云 `klyric` 的 `<offset,duration>` 标记，
 * 没有时按 LRC 行时长与字数合成扫光节奏（与 iOS `KaraokeLyrics` 一致）。
 */
class KaraokeLyrics(
    val lines: List<KaraokeLine> = emptyList(),
    val isSynthesized: Boolean = false,
) {
    val hasTranslation: Boolean get() = lines.any { !it.translation.isNullOrEmpty() }

    val hasRomanization: Boolean get() = lines.any { !it.romanization.isNullOrEmpty() }

    constructor(info: LyricInfo) : this(build(info))

    private constructor(built: Pair<List<KaraokeLine>, Boolean>) : this(built.first, built.second)

    fun currentIndex(atSeconds: Double): Int? {
        if (lines.isEmpty()) return null
        val milliseconds = max(0.0, atSeconds) * 1_000
        var low = 0
        var high = lines.size
        while (low < high) {
            val middle = (low + high) / 2
            if (lines[middle].startMs <= milliseconds) low = middle + 1 else high = middle
        }
        return max(0, low - 1)
    }

    private companion object {
        const val TRANSLATION_TOLERANCE_MS = 120.0
        const val FALLBACK_LAST_LINE_DURATION_MS = 4_000
        const val FALLBACK_SWEEP_RATIO = 0.88

        val timestampExpression = Regex("""\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?]""")
        val timedTokenExpression = Regex("""<(\d+),(\d+)>([^<]*)""")
        val fallbackTokenExpression = Regex("""[぀-ヿ㐀-䶿一-鿿]|[^぀-ヿ㐀-䶿一-鿿\s]+\s*|\s+""")

        data class RawToken(val text: String, val startMs: Int, val endMs: Int)
        data class RawLine(val startMs: Int, val endMs: Int, val text: String, val tokens: List<RawToken>)

        fun build(info: LyricInfo): Pair<List<KaraokeLine>, Boolean> {
            val translations = LrcParser.parse(LyricInfo(lyric = info.translation.orEmpty()))
            val romanizations = LrcParser.parse(LyricInfo(lyric = info.romanization.orEmpty()))
            val timed = parseTimed(info.karaoke)
            val parsed = timed ?: synthesizeFallback(info.lyric)
            val synthesized = timed == null
            val lines = parsed.mapIndexed { index, raw ->
                KaraokeLine(
                    id = index,
                    startMs = raw.startMs,
                    endMs = raw.endMs,
                    text = raw.text,
                    translation = nearestText(raw.startMs, translations, TRANSLATION_TOLERANCE_MS),
                    romanization = nearestText(raw.startMs, romanizations, TRANSLATION_TOLERANCE_MS),
                    tokens = raw.tokens.mapIndexed { tokenIndex, token ->
                        KaraokeToken(tokenIndex, token.text, token.startMs, token.endMs)
                    },
                )
            }
            return lines to synthesized
        }

        fun parseTimed(text: String?): List<RawLine>? {
            if (text.isNullOrBlank()) return null
            val parsed = mutableListOf<Pair<Int, RawLine>>()
            var timestampLineCount = 0

            text.lineSequence().forEachIndexed { order, sourceLine ->
                val line = sourceLine.trim()
                if (line.isEmpty()) return@forEachIndexed
                val timestamps = timestampExpression.findAll(line).toList()
                if (timestamps.isEmpty()) return@forEachIndexed
                timestampLineCount++
                val contentStart = timestamps.maxOf { it.range.last + 1 }
                if (contentStart > line.length) return null
                val content = line.substring(contentStart)
                val relativeTokens = parseTimedTokens(content) ?: return null
                timestamps.forEach { timestamp ->
                    val startMs = timestampMilliseconds(timestamp, line) ?: return null
                    val tokens = relativeTokens.map { token ->
                        RawToken(token.text, startMs + token.startMs, startMs + token.endMs)
                    }
                    parsed += order to RawLine(
                        startMs = startMs,
                        endMs = max(startMs + 1, tokens.maxOfOrNull { it.endMs } ?: (startMs + 1)),
                        text = tokens.joinToString("") { it.text }.trim(),
                        tokens = tokens,
                    )
                }
            }

            if (timestampLineCount == 0 || parsed.isEmpty()) return null
            val sorted = parsed
                .sortedWith(compareBy<Pair<Int, RawLine>> { it.second.startMs }.thenBy { it.first })
                .map { it.second }
            return sorted.mapIndexed { index, line ->
                val nextStart = sorted.getOrNull(index + 1)?.startMs
                RawLine(
                    startMs = line.startMs,
                    endMs = max(line.startMs + 1, nextStart ?: line.endMs),
                    text = line.text,
                    tokens = line.tokens,
                )
            }
        }

        fun parseTimedTokens(content: String): List<RawToken>? {
            val matches = timedTokenExpression.findAll(content).toList()
            if (matches.isEmpty()) return null
            var cursor = 0
            val tokens = mutableListOf<RawToken>()
            for (match in matches) {
                if (match.range.first != cursor) return null
                val offset = match.groupValues[1].toIntOrNull() ?: return null
                val duration = match.groupValues[2].toIntOrNull() ?: return null
                val tokenText = match.groupValues[3]
                if (tokenText.isEmpty()) return null
                tokens += RawToken(tokenText, offset, offset + max(1, duration))
                cursor = match.range.last + 1
            }
            if (cursor != content.length) return null
            if (tokens.joinToString("") { it.text }.isBlank()) return null
            return tokens
        }

        fun synthesizeFallback(lyric: String): List<RawLine> {
            val lines = LrcParser.parse(LyricInfo(lyric = lyric))
            return lines.mapIndexed { index, line ->
                val startMs = line.timeMs.toInt()
                val nextMs = lines.getOrNull(index + 1)?.timeMs?.toInt()
                    ?: (startMs + FALLBACK_LAST_LINE_DURATION_MS)
                val endMs = max(startMs + 1, nextMs)
                val tokenTexts = splitFallbackTokens(line.text)
                val weights = tokenTexts.map(::tokenWeight)
                val totalWeight = weights.sum()
                val sweepDuration = (endMs - startMs) * FALLBACK_SWEEP_RATIO
                var cursor = startMs.toDouble()
                val tokens = tokenTexts.zip(weights).map { (text, weight) ->
                    val duration = if (totalWeight > 0) sweepDuration * weight / totalWeight else 0.0
                    val token = RawToken(
                        text = text,
                        startMs = cursor.toInt(),
                        endMs = (cursor + max(1.0, duration)).toInt(),
                    )
                    cursor += duration
                    token
                }
                RawLine(startMs, endMs, line.text, tokens)
            }
        }

        fun splitFallbackTokens(text: String): List<String> {
            val tokens = fallbackTokenExpression.findAll(text).map { it.value }.toList()
            return tokens.ifEmpty { listOf(text) }
        }

        fun tokenWeight(token: String): Double {
            if (token.all { it.isWhitespace() }) return 0.25
            if (token.any { it.isCjk() }) return 1.0
            val length = token.trim().length
            return 0.5 + 0.11 * length
        }

        fun Char.isCjk(): Boolean = code in 0x3040..0x30FF ||
            code in 0x3400..0x4DBF ||
            code in 0x4E00..0x9FFF ||
            code in 0xF900..0xFAFF ||
            code in 0xFF66..0xFF9F

        fun nearestText(milliseconds: Int, lines: List<LyricLine>, toleranceMs: Double): String? =
            lines
                .map { it to abs(it.timeMs - milliseconds) }
                .filter { it.second <= toleranceMs + 0.001 }
                .minByOrNull { it.second }
                ?.first
                ?.text

        fun timestampMilliseconds(match: MatchResult, text: String): Int? {
            val minute = match.groupValues[1].toIntOrNull() ?: return null
            val second = match.groupValues[2].toIntOrNull() ?: return null
            val fractionText = match.groupValues[3]
            val fraction = when (fractionText.length) {
                0 -> 0
                1 -> fractionText.toIntOrNull()?.times(100) ?: 0
                2 -> fractionText.toIntOrNull()?.times(10) ?: 0
                else -> fractionText.take(3).toIntOrNull() ?: 0
            }
            return (minute * 60 + second) * 1_000 + fraction
        }
    }
}
