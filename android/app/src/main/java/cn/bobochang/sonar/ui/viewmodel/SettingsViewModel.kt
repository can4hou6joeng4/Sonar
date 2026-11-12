package cn.bobochang.sonar.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import cn.bobochang.sonar.data.model.Quality
import cn.bobochang.sonar.data.net.SourceException
import cn.bobochang.sonar.data.prefs.SonarSettings
import cn.bobochang.sonar.data.prefs.ThemeMode
import cn.bobochang.sonar.di.AppContainer
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class CredentialState(
    val hasCookie: Boolean = false,
    val hasChkszKey: Boolean = false,
    val accountName: String? = null,
    val vipType: Int = 0,
    val checking: Boolean = false,
    val error: String? = null,
)

class SettingsViewModel(private val container: AppContainer) : ViewModel() {
    val settings: StateFlow<SonarSettings> = container.settings.settings
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), SonarSettings())

    val cacheCount: StateFlow<Int> = container.audioCache.observeCount()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), 0)

    val cacheBytes: StateFlow<Long> = container.audioCache.observeBytes()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), 0L)

    private val _credentials = MutableStateFlow(CredentialState())
    val credentials: StateFlow<CredentialState> = _credentials.asStateFlow()

    private val _messages = MutableSharedFlow<String>(extraBufferCapacity = 4)
    val messages = _messages.asSharedFlow()

    init {
        refreshCredentialFlags()
    }

    fun saveCookie(raw: String?) {
        runCatching {
            container.credentials.saveNeteaseCookie(raw)
            refreshCredentialFlags()
        }.onSuccess {
            viewModelScope.launch {
                _messages.emit(if (raw.isNullOrBlank()) "已清除网易云 Cookie" else "已保存网易云 Cookie")
            }
        }.onFailure {
            viewModelScope.launch { _messages.emit("保存 Cookie 失败") }
        }
    }

    fun saveChkszKey(raw: String?) {
        runCatching {
            container.credentials.saveChkszKey(raw)
            container.chksz.resetCircuit()
            refreshCredentialFlags()
        }.onSuccess {
            viewModelScope.launch {
                _messages.emit(if (raw.isNullOrBlank()) "已清除 ChKSz Key" else "已保存 ChKSz Key")
            }
        }.onFailure {
            viewModelScope.launch { _messages.emit("保存 Key 失败") }
        }
    }

    fun verifyAccount() {
        if (!container.credentials.hasNeteaseCookie()) {
            _credentials.update { it.copy(error = "请先保存网易云 Cookie", accountName = null) }
            return
        }
        _credentials.update { it.copy(checking = true, error = null) }
        viewModelScope.launch {
            runCatching { container.netEase.account() }
                .onSuccess { (nickname, vipType) ->
                    _credentials.update {
                        it.copy(checking = false, accountName = nickname, vipType = vipType, error = null)
                    }
                }
                .onFailure { error ->
                    _credentials.update {
                        it.copy(
                            checking = false,
                            accountName = null,
                            error = (error as? SourceException)?.message ?: "登录态校验失败",
                        )
                    }
                }
        }
    }

    fun setQuality(quality: Quality) = launchSetting { container.settings.setQuality(quality) }

    fun setAutoCache(enabled: Boolean) = launchSetting { container.settings.setAutoCache(enabled) }

    fun setCellularWifiOnly(enabled: Boolean) =
        launchSetting { container.settings.setCellularWifiOnly(enabled) }

    fun setThemeMode(mode: ThemeMode) = launchSetting { container.settings.setThemeMode(mode) }

    fun setLyricsOffset(ms: Long) = launchSetting { container.settings.setLyricsOffsetMs(ms) }

    fun clearCache() {
        viewModelScope.launch {
            val (count, bytes) = withContext(Dispatchers.IO) { container.audioCache.clear() }
            _messages.emit("已清除 $count 首缓存，释放 ${formatBytes(bytes)}")
        }
    }

    private fun refreshCredentialFlags() {
        _credentials.update {
            it.copy(
                hasCookie = container.credentials.hasNeteaseCookie(),
                hasChkszKey = container.credentials.hasChkszKey(),
            )
        }
    }

    private fun launchSetting(block: suspend () -> Unit) {
        viewModelScope.launch { runCatching { block() } }
    }

    companion object {
        fun formatBytes(bytes: Long): String = when {
            bytes >= 1_000_000_000 -> "%.1f GB".format(bytes / 1_000_000_000.0)
            bytes >= 1_000_000 -> "%.1f MB".format(bytes / 1_000_000.0)
            bytes >= 1_000 -> "%.0f KB".format(bytes / 1_000.0)
            else -> "$bytes B"
        }
    }
}
