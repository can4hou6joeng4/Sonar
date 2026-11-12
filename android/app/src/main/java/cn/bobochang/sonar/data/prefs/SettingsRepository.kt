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

enum class ThemeMode { SYSTEM, DARK, LIGHT }

data class SonarSettings(
    val quality: Quality = Quality.MASTER,
    val autoCache: Boolean = true,
    val cellularWifiOnly: Boolean = true,
    val themeMode: ThemeMode = ThemeMode.SYSTEM,
    val lyricsOffsetMs: Long = 0L,
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

    suspend fun setLyricsOffsetMs(offset: Long) {
        context.sonarSettingsDataStore.edit { it[Keys.LYRICS_OFFSET] = offset.coerceIn(-5_000, 5_000) }
    }

    suspend fun setLastTab(index: Int) {
        context.sonarSettingsDataStore.edit { it[Keys.LAST_TAB] = index.coerceIn(0, 3) }
    }

    private fun mapPreferences(preferences: androidx.datastore.preferences.core.Preferences): SonarSettings =
        SonarSettings(
            quality = Quality.fromWire(preferences[Keys.QUALITY]) ?: Quality.MASTER,
            autoCache = preferences[Keys.AUTO_CACHE] ?: true,
            cellularWifiOnly = preferences[Keys.CELLULAR_WIFI_ONLY] ?: true,
            themeMode = runCatching {
                ThemeMode.valueOf(preferences[Keys.THEME_MODE] ?: ThemeMode.SYSTEM.name)
            }.getOrDefault(ThemeMode.SYSTEM),
            lyricsOffsetMs = preferences[Keys.LYRICS_OFFSET] ?: 0L,
            lastTab = preferences[Keys.LAST_TAB] ?: 0,
        )

    private object Keys {
        val QUALITY = stringPreferencesKey("quality")
        val AUTO_CACHE = booleanPreferencesKey("auto_cache")
        val CELLULAR_WIFI_ONLY = booleanPreferencesKey("cellular_wifi_only")
        val THEME_MODE = stringPreferencesKey("theme_mode")
        val LYRICS_OFFSET = longPreferencesKey("lyrics_offset_ms")
        val LAST_TAB = intPreferencesKey("last_tab")
    }
}
