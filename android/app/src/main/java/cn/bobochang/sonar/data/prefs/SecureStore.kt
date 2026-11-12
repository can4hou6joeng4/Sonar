package cn.bobochang.sonar.data.prefs

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import cn.bobochang.sonar.data.net.NetEaseWebClient
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class SecureStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences("sonar_secure", Context.MODE_PRIVATE)

    fun put(name: String, value: String?) {
        val trimmed = value?.trim().orEmpty()
        if (trimmed.isEmpty()) {
            prefs.edit().remove(name).apply()
            return
        }
        runCatching {
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.ENCRYPT_MODE, secretKey())
            val payload = Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" +
                Base64.encodeToString(cipher.doFinal(trimmed.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
            prefs.edit().putString(name, payload).apply()
        }
    }

    fun get(name: String): String? {
        val stored = prefs.getString(name, null) ?: return null
        return runCatching {
            val parts = stored.split(":", limit = 2)
            require(parts.size == 2)
            val iv = Base64.decode(parts[0], Base64.NO_WRAP)
            val ciphertext = Base64.decode(parts[1], Base64.NO_WRAP)
            val cipher = Cipher.getInstance(TRANSFORMATION)
            cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, iv))
            String(cipher.doFinal(ciphertext), Charsets.UTF_8)
        }.getOrElse {
            prefs.edit().remove(name).apply()
            null
        }
    }

    private fun secretKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (keyStore.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    private companion object {
        const val ANDROID_KEYSTORE = "AndroidKeyStore"
        const val KEY_ALIAS = "sonar_secure_key"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
    }
}

class CredentialStore(context: Context) {
    private val secure = SecureStore(context)
    private val bundled: Map<String, String> = runCatching {
        context.assets.open("build_credentials.json").bufferedReader().use { reader ->
            val element = kotlinx.serialization.json.Json.parseToJsonElement(reader.readText())
            val obj = element.jsonObject
            obj.keys.associateWith { key ->
                (obj[key] as? kotlinx.serialization.json.JsonPrimitive)?.content.orEmpty()
            }.filterValues { it.isNotBlank() }
        }
    }.getOrDefault(emptyMap())

    fun neteaseCookie(): String? =
        NetEaseWebClient.normalizeCookie(secure.get(KEY_COOKIE))
            ?: NetEaseWebClient.normalizeCookie(bundled["neteaseCookie"])
            ?: NetEaseWebClient.normalizeCookie(bundled["wyToken"])

    fun saveNeteaseCookie(raw: String?) {
        secure.put(KEY_COOKIE, NetEaseWebClient.normalizeCookie(raw))
    }

    fun chkszKey(): String? =
        secure.get(KEY_CHKSZ)?.trim()?.takeIf { it.isNotEmpty() }
            ?: bundled["chkszKey"]?.trim()?.takeIf { it.isNotEmpty() }

    fun saveChkszKey(raw: String?) {
        secure.put(KEY_CHKSZ, raw)
    }

    fun hasNeteaseCookie(): Boolean = !neteaseCookie().isNullOrBlank()

    fun hasChkszKey(): Boolean = !chkszKey().isNullOrBlank()

    private companion object {
        const val KEY_COOKIE = "netease_cookie"
        const val KEY_CHKSZ = "chksz_key"
    }
}
