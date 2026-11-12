package cn.bobochang.sonar.data.prefs

import android.content.Context
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.emptyPreferences
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import cn.bobochang.sonar.data.model.Quality
import cn.bobochang.sonar.data.model.wire
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject

enum class ThemeMode { SYSTEM, DARK, LIGHT }

data class SonarSettings(
    val quality: Quality = Quality.MASTER,
    val autoCache: Boolean = true,
    val cellularWifiOnly: Boolean = true,
    val themeMode: ThemeMode = ThemeMode.SYSTEM,
    val coverAccentEnabled: Boolean = true,
    val lyricsOffsetMs: Long = 0L,
    val lyricsOffsets: Map<String, Long> = emptyMap(),
    val lastTab: Int = 0,
)

private val Context.sonarSettingsDataStore by preferencesDataStore(name = "sonar_settings")

class SettingsRepository(private val context: Context) {
    val settings: Flow<SonarSettings> = context.sonarSettingsDataStore.data
        .catch { emit(emptyPreferences()) }
        .map(::mapPreferences)

    suspend fun snapshot(): SonarSettings = settings.first()

    suspend fun setQuality(quality: Quality) {
        context.sonarSettingsDataStore.edit { it[Keys.QUALITY] = quality.wire }
    }

    suspend fun setAutoCache(enabled: Boolean) {
        context.sonarSettingsDataStore.edit { it[Keys.AUTO_CACHE] = enabled }
    }

    suspend fun setCellularWifiOnly(enabled: Boolean) {
        context.sonarSettingsDataStore.edit { it[Keys.CELLULAR_WIFI_ONLY] = enabled }
    }

    suspend fun setThemeMode(mode: ThemeMode) {
        context.sonarSettingsDataStore.edit { it[Keys.THEME_MODE] = mode.name }
    }

    suspend fun setCoverAccentEnabled(enabled: Boolean) {
        context.sonarSettingsDataStore.edit { it[Keys.COVER_ACCENT] = enabled }
    }

    suspend fun setLyricsOffsetMs(offset: Long) {
        context.sonarSettingsDataStore.edit { it[Keys.LYRICS_OFFSET] = offset.coerceIn(-5_000, 5_000) }
    }

    suspend fun setLastTab(index: Int) {
        context.sonarSettingsDataStore.edit { it[Keys.LAST_TAB] = index.coerceIn(0, 3) }
    }

    /** 逐曲歌词偏移（秒）。正值表示歌词整体延后显示。 */
    suspend fun lyricsOffsetSeconds(musicId: String?): Float {
        if (musicId.isNullOrBlank()) return 0f
        val offsets = decodeOffsets(context.sonarSettingsDataStore.data.first()[Keys.LYRICS_OFFSETS])
        return (offsets[musicId] ?: 0L) / 1000f
    }

    suspend fun adjustLyricsOffsetSeconds(musicId: String?, delta: Float): Float {
        if (musicId.isNullOrBlank()) return 0f
        var result = 0f
        context.sonarSettingsDataStore.edit { preferences ->
            val offsets = decodeOffsets(preferences[Keys.LYRICS_OFFSETS]).toMutableMap()
            val next = ((offsets[musicId] ?: 0L) + (delta * 1000).toLong())
                .coerceIn(-5_000L, 5_000L)
            if (next == 0L) offsets.remove(musicId) else offsets[musicId] = next
            preferences[Keys.LYRICS_OFFSETS] = encodeOffsets(offsets)
            result = next / 1000f
        }
        return result
    }

    suspend fun resetLyricsOffset(musicId: String?) {
        if (musicId.isNullOrBlank()) return
        context.sonarSettingsDataStore.edit { preferences ->
            val offsets = decodeOffsets(preferences[Keys.LYRICS_OFFSETS]).toMutableMap()
            offsets.remove(musicId)
            preferences[Keys.LYRICS_OFFSETS] = encodeOffsets(offsets)
        }
    }

    private fun decodeOffsets(raw: String?): Map<String, Long> {
        if (raw.isNullOrBlank()) return emptyMap()
        return runCatching {
            Json.parseToJsonElement(raw).jsonObject.mapNotNull { (key, value) ->
                val number = (value as? JsonPrimitive)?.content?.toLongOrNull() ?: return@mapNotNull null
                key to number
            }.toMap()
        }.getOrDefault(emptyMap())
    }

    private fun encodeOffsets(offsets: Map<String, Long>): String =
        JsonObject(offsets.mapValues { JsonPrimitive(it.value) }).toString()

    private fun mapPreferences(preferences: androidx.datastore.preferences.core.Preferences): SonarSettings =
        SonarSettings(
            quality = Quality.fromWire(preferences[Keys.QUALITY]) ?: Quality.MASTER,
            autoCache = preferences[Keys.AUTO_CACHE] ?: true,
            cellularWifiOnly = preferences[Keys.CELLULAR_WIFI_ONLY] ?: true,
            themeMode = runCatching {
                ThemeMode.valueOf(preferences[Keys.THEME_MODE] ?: ThemeMode.SYSTEM.name)
            }.getOrDefault(ThemeMode.SYSTEM),
            coverAccentEnabled = preferences[Keys.COVER_ACCENT] ?: true,
            lyricsOffsetMs = preferences[Keys.LYRICS_OFFSET] ?: 0L,
            lyricsOffsets = decodeOffsets(preferences[Keys.LYRICS_OFFSETS]),
            lastTab = preferences[Keys.LAST_TAB] ?: 0,
        )

    private object Keys {
        val QUALITY = stringPreferencesKey("quality")
        val AUTO_CACHE = booleanPreferencesKey("auto_cache")
        val CELLULAR_WIFI_ONLY = booleanPreferencesKey("cellular_wifi_only")
        val THEME_MODE = stringPreferencesKey("theme_mode")
        val COVER_ACCENT = booleanPreferencesKey("cover_accent_enabled")
        val LYRICS_OFFSET = longPreferencesKey("lyrics_offset_ms")
        val LYRICS_OFFSETS = stringPreferencesKey("lyrics_offsets")
        val LAST_TAB = intPreferencesKey("last_tab")
    }
}
