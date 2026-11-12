package cn.bobochang.sonar.ui.artwork

import android.content.Context
import android.graphics.Bitmap
import androidx.core.graphics.drawable.toBitmap
import cn.bobochang.sonar.ui.components.normalizedImageUrl
import coil.imageLoader
import coil.request.ImageRequest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * iOS `ArtworkPalette.accentHex(from:)` 的 Kotlin 移植：
 * 下采样到 44×44，按 15° 分 24 个色相桶，以饱和度 × 明度权重选主色。
 */
object ArtworkPalette {
    const val FALLBACK_HUE = 40f

    suspend fun accentHue(context: Context, url: String?): Float? = withContext(Dispatchers.IO) {
        val bitmap = loadBitmap(context, url, 44) ?: return@withContext null
        val hue = accentHueFrom(bitmap)
        bitmap.recycle()
        hue
    }

    suspend fun loadBitmap(context: Context, url: String?, size: Int): Bitmap? {
        if (url.isNullOrBlank()) return null
        return runCatching {
            val request = ImageRequest.Builder(context)
                .data(normalizedImageUrl(url))
                .allowHardware(false)
                .size(size)
                .build()
            val result = context.imageLoader.execute(request)
            val drawable = result.drawable ?: return@runCatching null
            drawable.toBitmap(size, size)
        }.getOrNull()
    }

    fun accentHueFrom(bitmap: Bitmap): Float? {
        val width = 44
        val height = 44
        val scaled = Bitmap.createScaledBitmap(bitmap, width, height, true)
        val pixels = IntArray(width * height)
        scaled.getPixels(pixels, 0, width, 0, 0, width, height)
        if (scaled !== bitmap) scaled.recycle()

        data class Bucket(var weight: Double = 0.0, var h: Double = 0.0, var s: Double = 0.0, var l: Double = 0.0)

        val buckets = Array(24) { Bucket() }
        for (pixel in pixels) {
            val alpha = (pixel ushr 24 and 0xFF) / 255.0
            if (alpha < 200.0 / 255.0) continue
            val r = (pixel shr 16 and 0xFF) / 255.0
            val g = (pixel shr 8 and 0xFF) / 255.0
            val b = (pixel and 0xFF) / 255.0
            val maximum = max(r, max(g, b))
            val minimum = min(r, min(g, b))
            val delta = maximum - minimum
            val lightness = (maximum + minimum) * 50
            val saturation = if (delta == 0.0) 0.0 else delta / (1 - abs(2 * lightness / 100 - 1)) * 100
            val hue = when {
                delta == 0.0 -> 0.0
                maximum == r -> 60 * (((g - b) / delta) % 6)
                maximum == g -> 60 * (((b - r) / delta) + 2)
                else -> 60 * (((r - g) / delta) + 4)
            }.let { if (it >= 0) it else it + 360 }
            if (lightness < 12 || lightness > 92 || saturation < 14) continue
            val weight = saturation * (1 - abs(lightness - 55) / 70)
            if (weight <= 0) continue
            val bucket = buckets[min(23, (hue / 15).toInt())]
            bucket.weight += weight
            bucket.h += hue * weight
            bucket.s += saturation * weight
            bucket.l += lightness * weight
        }

        val best = buckets.maxByOrNull { it.weight } ?: return null
        if (best.weight <= 0) return null
        val saturation = best.s / best.weight
        if (saturation < 12) return null
        return ((best.h / best.weight) % 360).toFloat()
    }

    /** 与 `M3Scheme.normalizedHex` 对齐的十六进制辅助。 */
    fun normalizedHex(value: String): String? {
        var digits = value.trim()
        if (digits.startsWith("#")) digits = digits.drop(1)
        if (digits.length == 3) digits = digits.map { "$it$it" }.joinToString("")
        if (digits.length != 6 || digits.toLongOrNull(16) == null) return null
        return "#${digits.uppercase()}"
    }

    fun hueToRgb(hue: Float, saturation: Float, value: Float): Triple<Int, Int, Int> {
        val h = (hue % 360 + 360) % 360
        val chroma = value * saturation
        val x = chroma * (1 - abs((h / 60) % 2 - 1))
        val m = value - chroma
        val (r, g, b) = when {
            h < 60 -> Triple(chroma, x, 0f)
            h < 120 -> Triple(x, chroma, 0f)
            h < 180 -> Triple(0f, chroma, x)
            h < 240 -> Triple(0f, x, chroma)
            h < 300 -> Triple(x, 0f, chroma)
            else -> Triple(chroma, 0f, x)
        }
        return Triple(
            ((r + m) * 255).roundToInt().coerceIn(0, 255),
            ((g + m) * 255).roundToInt().coerceIn(0, 255),
            ((b + m) * 255).roundToInt().coerceIn(0, 255),
        )
    }
}
