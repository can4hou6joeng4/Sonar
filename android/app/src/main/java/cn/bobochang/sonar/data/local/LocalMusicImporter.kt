package cn.bobochang.sonar.data.local

import android.content.Context
import android.content.Intent
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.OpenableColumns
import androidx.core.net.toUri
import androidx.documentfile.provider.DocumentFile
import cn.bobochang.sonar.data.model.MusicSource
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.data.model.formatDurationMs
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.io.File
import java.security.MessageDigest

class LocalMusicImporter(private val context: Context) {
    suspend fun importUris(uris: List<Uri>): List<Track> = withContext(Dispatchers.IO) {
        uris.forEach { uri ->
            runCatching {
                context.contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            }
        }
        uris.mapNotNull { uri -> importUri(uri) }
    }

    suspend fun importTree(treeUri: Uri): List<Track> = withContext(Dispatchers.IO) {
        runCatching {
            context.contentResolver.takePersistableUriPermission(
                treeUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        }
        val root = DocumentFile.fromTreeUri(context, treeUri) ?: return@withContext emptyList()
        val result = mutableListOf<Track>()
        traverse(root, result)
        result
    }

    private fun traverse(directory: DocumentFile, output: MutableList<Track>) {
        val children = runCatching { directory.listFiles().toList() }.getOrDefault(emptyList())
        val lrcFiles = children.filter { it.isFile && it.name?.endsWith(".lrc", ignoreCase = true) == true }
            .associateBy { it.name?.substringBeforeLast('.')?.lowercase() }
        for (file in children) {
            if (file.isDirectory) {
                traverse(file, output)
                continue
            }
            if (!file.isFile) continue
            val name = file.name ?: continue
            if (!isAudio(name, file.type)) continue
            val base = name.substringBeforeLast('.').lowercase()
            val lrc = lrcFiles[base]
            importDocument(file.uri, lrc?.uri, file.name, file.length(), file.type)
                ?.let(output::add)
        }
    }

    private fun importUri(uri: Uri): Track? {
        val displayName = queryDisplayName(uri) ?: uri.lastPathSegment ?: "本地音频"
        val lrc = if (uri.scheme == "file") {
            val audio = File(uri.path ?: return null)
            val sibling = File(audio.parentFile, audio.nameWithoutExtension + ".lrc")
            sibling.takeIf { it.exists() }?.toUri()
        } else {
            null
        }
        return importDocument(uri, lrc, displayName, null, null)
    }

    private fun importDocument(
        uri: Uri,
        lrcUri: Uri?,
        displayName: String?,
        knownSize: Long?,
        mimeType: String?,
    ): Track? {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(context, uri)
        } catch (_: Throwable) {
            retriever.release()
            return null
        }
        val name = displayName?.takeIf { it.isNotBlank() }
            ?: uri.lastPathSegment
            ?: "本地音频"
        val title = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_TITLE)
            ?.trim()?.takeIf { it.isNotEmpty() }
            ?: name.substringBeforeLast('.')
        val artist = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ARTIST)
            ?.trim()?.takeIf { it.isNotEmpty() }
            ?: "未知歌手"
        val album = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_ALBUM)
            ?.trim()?.takeIf { it.isNotEmpty() }
            ?: "本地音乐"
        val durationMs = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
            ?.toLongOrNull()
        val artworkUri = retriever.embeddedPicture?.let(::saveArtwork)
        retriever.release()

        val payload = buildJsonObject {
            put("uri", uri.toString())
            put("filename", name)
            mimeType?.let { put("mimeType", it) }
            knownSize?.takeIf { it > 0 }?.let { put("fileSize", it) }
            artworkUri?.let { put("artworkUri", it) }
            lrcUri?.let { put("lrcUri", it.toString()) }
            if (uri.scheme == "file") uri.path?.let { put("filePath", it) }
        }
        return Track(
            source = MusicSource.LOCAL,
            songmid = uri.toString(),
            title = title,
            artist = artist,
            album = album,
            interval = durationMs?.let(::formatDurationMs),
            payload = payload,
        )
    }

    private fun saveArtwork(bytes: ByteArray): String? = runCatching {
        val dir = File(context.filesDir, "local_artwork").apply { mkdirs() }
        val digest = MessageDigest.getInstance("SHA-1").digest(bytes)
        val name = digest.joinToString("") { "%02x".format(it) } + ".jpg"
        val file = File(dir, name)
        if (!file.exists()) file.writeBytes(bytes)
        Uri.fromFile(file).toString()
    }.getOrNull()

    private fun queryDisplayName(uri: Uri): String? = runCatching {
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor ->
                if (cursor.moveToFirst()) cursor.getString(0) else null
            }
    }.getOrNull()

    private fun isAudio(name: String, mimeType: String?): Boolean {
        if (mimeType?.startsWith("audio/") == true) return true
        val extension = name.substringAfterLast('.', "").lowercase()
        return extension in AUDIO_EXTENSIONS
    }

    private companion object {
        val AUDIO_EXTENSIONS = setOf(
            "mp3", "flac", "m4a", "aac", "wav", "aiff", "aif", "alac", "ogg", "opus",
        )
    }
}
