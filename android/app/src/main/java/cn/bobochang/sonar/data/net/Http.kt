package cn.bobochang.sonar.data.net

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.IOException

object SonarHttp {
    val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, java.util.concurrent.TimeUnit.SECONDS)
        .readTimeout(30, java.util.concurrent.TimeUnit.SECONDS)
        .writeTimeout(30, java.util.concurrent.TimeUnit.SECONDS)
        .callTimeout(40, java.util.concurrent.TimeUnit.SECONDS)
        .followRedirects(true)
        .followSslRedirects(true)
        .build()

    val mediaClient: OkHttpClient = client.newBuilder()
        .connectTimeout(8, java.util.concurrent.TimeUnit.SECONDS)
        .readTimeout(8, java.util.concurrent.TimeUnit.SECONDS)
        .callTimeout(12, java.util.concurrent.TimeUnit.SECONDS)
        .build()

    /** 媒体 CDN 通常要求浏览器 UA；不要在这里附加任何账号凭据。 */
    fun mediaRequest(url: String): Request.Builder = Request.Builder()
        .url(url)
        .header("User-Agent", MEDIA_USER_AGENT)
        .header("Referer", "https://music.163.com/")

    private const val MEDIA_USER_AGENT =
        "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Mobile Safari/537.36"
}

class ConnectivityMonitor(private val context: Context) {
    private val manager: ConnectivityManager? =
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager

    fun isOnline(): Boolean = activeCapabilities() != null

    fun isUnmetered(): Boolean {
        val capabilities = activeCapabilities() ?: return false
        return capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) &&
            capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
    }

    fun isCellular(): Boolean {
        val capabilities = activeCapabilities() ?: return false
        return !capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
    }

    private fun activeCapabilities(): NetworkCapabilities? {
        val network = manager?.activeNetwork ?: return null
        return manager.getNetworkCapabilities(network)
    }
}

sealed class SourceException(message: String, cause: Throwable? = null) : Exception(message, cause) {
    class Network(cause: Throwable) : SourceException("网络失败", cause)
    class Message(message: String) : SourceException(message)
    class CredentialRequired(message: String) : SourceException(message)
    class Unavailable(message: String) : SourceException(message)
    class TrialOnly : SourceException("仅返回试听片段")
}

internal fun normalizeHttps(raw: String): String? {
    val url: HttpUrl = raw.toHttpUrlOrNull() ?: return null
    if (url.username.isNotEmpty() || url.password.isNotEmpty()) return null
    return url.newBuilder().scheme("https").build().toString()
}

/** 播放链接必须真实返回媒体内容，避免把 HTML/JSON 错误页当作音频。 */
suspend fun probeMediaUrl(url: String): Boolean = withContext(Dispatchers.IO) {
    runCatching {
        val request = SonarHttp.mediaRequest(url)
            .header("Range", "bytes=0-1")
            .build()
        SonarHttp.mediaClient.newCall(request).execute().use { response ->
            if (response.code !in 200..299) return@use false
            val contentType = response.header("Content-Type")?.lowercase().orEmpty()
            if (contentType.startsWith("text/") ||
                contentType.contains("html") ||
                contentType.contains("json") ||
                contentType.contains("xml")
            ) {
                return@use false
            }
            if (contentType.startsWith("audio/") || contentType == "application/octet-stream") {
                return@use true
            }
            val body = response.body ?: return@use false
            val buffer = ByteArray(64)
            val read = body.byteStream().read(buffer)
            if (read <= 0) return@use false
            val prefix = String(buffer, 0, read, Charsets.UTF_8).trim().lowercase()
            !(prefix.startsWith("<") ||
                prefix.startsWith("{") ||
                prefix.startsWith("[") ||
                prefix.startsWith("error"))
        }
    }.getOrDefault(false)
}

fun Throwable.toSourceException(): SourceException = when (this) {
    is SourceException -> this
    is IOException -> SourceException.Network(this)
    else -> SourceException.Message(message ?: "请求失败")
}
