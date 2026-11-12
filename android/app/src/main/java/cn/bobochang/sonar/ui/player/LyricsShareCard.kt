package cn.bobochang.sonar.ui.player

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Shader
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import androidx.core.content.FileProvider
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.lyrics.KaraokeLyrics
import cn.bobochang.sonar.ui.artwork.ArtworkPalette
import java.io.File
import java.io.FileOutputStream

/** 对应 iOS `LyricsShareCard`：330×440 的歌词卡片，3 倍出图后走系统分享。 */
object LyricsShareCardRenderer {
    private const val WIDTH = 330f
    private const val HEIGHT = 440f

    suspend fun share(
        context: Context,
        track: Track,
        lyrics: KaraokeLyrics,
        elapsedMs: Long,
    ): Boolean {
        val bitmap = runCatching { render(context, track, lyrics, elapsedMs) }.getOrNull() ?: return false
        val directory = File(context.cacheDir, "share-cards").apply { mkdirs() }
        directory.listFiles()?.sortedByDescending { it.lastModified() }?.drop(4)?.forEach { it.delete() }
        val file = File(directory, "lyrics-${System.currentTimeMillis()}.png")
        val saved = runCatching {
            FileOutputStream(file).use { output -> bitmap.compress(Bitmap.CompressFormat.PNG, 100, output) }
        }.isSuccess
        bitmap.recycle()
        if (!saved) return false

        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        val intent = Intent(Intent.ACTION_SEND).apply {
            type = "image/png"
            putExtra(Intent.EXTRA_STREAM, uri)
            putExtra(Intent.EXTRA_SUBJECT, track.title)
            putExtra(Intent.EXTRA_TEXT, "${track.title} - ${track.artist}")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        return runCatching {
            context.startActivity(Intent.createChooser(intent, "分享歌词卡片").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        }.getOrDefault(false)
    }

    suspend fun render(
        context: Context,
        track: Track,
        lyrics: KaraokeLyrics,
        elapsedMs: Long,
    ): Bitmap {
        val scale = 3f
        val width = (WIDTH * scale).toInt()
        val height = (HEIGHT * scale).toInt()
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val background = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            shader = LinearGradient(
                0f, 0f, width.toFloat(), height.toFloat(),
                Color.rgb(0x22, 0x22, 0x2A), Color.rgb(0x0B, 0x0B, 0x0E),
                Shader.TileMode.CLAMP,
            )
        }
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), background)

        val padding = 22f * scale
        var top = padding

        val artworkSize = 64f * scale
        val artwork = ArtworkPalette.loadBitmap(context, track.coverUrl, artworkSize.toInt())
        if (artwork != null) {
            val rect = RectF(padding, top, padding + artworkSize, top + artworkSize)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG)
            val clip = android.graphics.Path().apply {
                addRoundRect(rect, 10f * scale, 10f * scale, android.graphics.Path.Direction.CW)
            }
            canvas.save()
            canvas.clipPath(clip)
            canvas.drawBitmap(artwork, null, rect, paint)
            canvas.restore()
            artwork.recycle()
        } else {
            val rect = RectF(padding, top, padding + artworkSize, top + artworkSize)
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.argb(31, 255, 255, 255) }
            canvas.drawRoundRect(rect, 10f * scale, 10f * scale, paint)
        }

        val titlePaint = textPaint(17f * scale, bold = true, alpha = 255)
        val artistPaint = textPaint(12f * scale, bold = false, alpha = 166)
        val textLeft = padding + artworkSize + 12f * scale
        val titleLayout = layout(track.title, titlePaint, (width - textLeft - padding).toInt(), maxLines = 1)
        canvas.save()
        canvas.translate(textLeft, top + 8f * scale)
        titleLayout.draw(canvas)
        canvas.restore()
        val artistLayout = layout(track.artist, artistPaint, (width - textLeft - padding).toInt(), maxLines = 1)
        canvas.save()
        canvas.translate(textLeft, top + 34f * scale)
        artistLayout.draw(canvas)
        canvas.restore()

        top += artworkSize + 20f * scale

        val lines = lines(lyrics, elapsedMs)
        lines.forEachIndexed { index, text ->
            val paint = textPaint(
                size = if (index == 0) 21f * scale else 17f * scale,
                bold = index == 0,
                alpha = if (index == 0) 255 else 184,
            )
            val staticLayout = layout(text, paint, (width - padding * 2).toInt(), maxLines = 2)
            canvas.save()
            canvas.translate(padding, top)
            staticLayout.draw(canvas)
            canvas.restore()
            top += staticLayout.height + 12f * scale
        }

        val footerY = height - padding - 14f * scale
        canvas.drawText(
            "Sonar",
            padding,
            footerY,
            textPaint(12f * scale, bold = true, alpha = 140),
        )
        val urlPaint = textPaint(9f * scale, bold = false, alpha = 90)
        val url = if (track.songmid.isNotBlank() && track.source == cn.bobochang.sonar.data.model.MusicSource.WY) {
            "music.163.com/song?id=${track.songmid}"
        } else {
            "Sonar · 在深水里，靠声音辨路"
        }
        canvas.drawText(
            url,
            width - padding - urlPaint.measureText(url),
            footerY,
            urlPaint,
        )
        return bitmap
    }

    fun lines(lyrics: KaraokeLyrics, elapsedMs: Long): List<String> {
        val all = lyrics.lines.filter { it.text.isNotBlank() }
        if (all.isEmpty()) return listOf("正在听")
        var index = all.indexOfFirst { it.endMs >= elapsedMs }.takeIf { it >= 0 } ?: 0
        index = index.coerceIn(0, all.lastIndex)
        return all.drop(index).take(4).map { it.text }
    }

    private fun textPaint(size: Float, bold: Boolean, alpha: Int): TextPaint =
        TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = size
            color = Color.argb(alpha, 255, 255, 255)
            typeface = Typeface.create(Typeface.DEFAULT, if (bold) Typeface.BOLD else Typeface.NORMAL)
        }

    private fun layout(text: String, paint: TextPaint, width: Int, maxLines: Int): StaticLayout =
        StaticLayout.Builder.obtain(text, 0, text.length, paint, width.coerceAtLeast(1))
            .setAlignment(Layout.Alignment.ALIGN_NORMAL)
            .setLineSpacing(0f, 1.25f)
            .setMaxLines(maxLines)
            .setEllipsize(android.text.TextUtils.TruncateAt.END)
            .build()
}
