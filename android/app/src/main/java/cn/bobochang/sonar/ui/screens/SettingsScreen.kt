package cn.bobochang.sonar.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.CheckCircle
import androidx.compose.material.icons.rounded.Key
import androidx.compose.material.icons.rounded.Person
import androidx.compose.material.icons.rounded.Subtitles
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import cn.bobochang.sonar.BuildConfig
import cn.bobochang.sonar.data.model.Quality
import cn.bobochang.sonar.data.prefs.ThemeMode
import cn.bobochang.sonar.di.AppContainer
import cn.bobochang.sonar.ui.theme.LocalSonarPalette
import cn.bobochang.sonar.ui.viewmodel.SettingsViewModel

@Composable
fun SettingsScreen(
    container: AppContainer,
    snackbarHostState: SnackbarHostState,
) {
    val vm: SettingsViewModel = viewModel(
        factory = viewModelFactory { initializer { SettingsViewModel(container) } },
    )
    val settings by vm.settings.collectAsStateWithLifecycle()
    val credentials by vm.credentials.collectAsStateWithLifecycle()
    val cacheCount by vm.cacheCount.collectAsStateWithLifecycle()
    val cacheBytes by vm.cacheBytes.collectAsStateWithLifecycle()
    val palette = LocalSonarPalette.current
    var cookieDialog by remember { mutableStateOf(false) }
    var keyDialog by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        vm.messages.collect { message -> snackbarHostState.showSnackbar(message) }
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.background),
        contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Column(modifier = Modifier.padding(horizontal = 4.dp, vertical = 8.dp)) {
                Text("设置", style = MaterialTheme.typography.headlineLarge, color = palette.ink)
                Text(
                    "账号、音质与离线缓存",
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.secondaryInk,
                )
            }
        }

        item {
            SettingsCard(title = "外观") {
                Text(
                    "主题",
                    style = MaterialTheme.typography.titleSmall,
                    color = palette.ink,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    ThemeMode.entries.forEach { mode ->
                        FilterChip(
                            selected = settings.themeMode == mode,
                            onClick = { vm.setThemeMode(mode) },
                            label = {
                                Text(
                                    when (mode) {
                                        ThemeMode.SYSTEM -> "跟随系统"
                                        ThemeMode.DARK -> "深色"
                                        ThemeMode.LIGHT -> "浅色"
                                    },
                                )
                            },
                            colors = FilterChipDefaults.filterChipColors(
                                selectedContainerColor = palette.accent.copy(alpha = 0.16f),
                                selectedLabelColor = palette.accent,
                            ),
                        )
                    }
                }
            }
        }

        item {
            SettingsCard(title = "账号与音源") {
                CredentialRow(
                    icon = Icons.Rounded.Person,
                    title = "网易云账号",
                    status = if (credentials.hasCookie) "已配置登录 Cookie" else "未配置，在线搜索与播放可能受限",
                    configured = credentials.hasCookie,
                    action = "配置",
                    onAction = { cookieDialog = true },
                )
                if (credentials.hasCookie) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        OutlinedButton(onClick = vm::verifyAccount, enabled = !credentials.checking) {
                            Text(if (credentials.checking) "校验中…" else "校验登录态")
                        }
                        Spacer(Modifier.size(10.dp))
                        credentials.accountName?.let { name ->
                            Icon(Icons.Rounded.CheckCircle, contentDescription = null, tint = palette.accent, modifier = Modifier.size(16.dp))
                            Spacer(Modifier.size(4.dp))
                            Text(name, style = MaterialTheme.typography.bodySmall, color = palette.secondaryInk)
                        }
                        credentials.error?.let { error ->
                            Text(error, style = MaterialTheme.typography.bodySmall, color = palette.accent)
                        }
                    }
                }
                HorizontalDivider(color = palette.divider)
                CredentialRow(
                    icon = Icons.Rounded.Key,
                    title = "ChKSz Key",
                    status = if (credentials.hasChkszKey) "已配置第三方音源凭据" else "未配置；网易云直连仍可使用",
                    configured = credentials.hasChkszKey,
                    action = "配置",
                    onAction = { keyDialog = true },
                )
                Text(
                    "凭据使用 Android Keystore 加密保存在本机，不会写入备份或日志。",
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.tertiaryInk,
                )
            }
        }

        item {
            SettingsCard(title = "播放音质") {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Quality.entries.forEach { quality ->
                        FilterChip(
                            selected = settings.quality == quality,
                            onClick = { vm.setQuality(quality) },
                            label = { Text(quality.displayName) },
                            colors = FilterChipDefaults.filterChipColors(
                                selectedContainerColor = palette.accent.copy(alpha = 0.16f),
                                selectedLabelColor = palette.accent,
                            ),
                        )
                    }
                }
                Text(
                    "从母带开始逐级回退：母带 → Hi-Res → 无损 → 320K → 128K。修改后对下一次播放生效。",
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.secondaryInk,
                )
            }
        }

        item {
            SettingsCard(title = "离线缓存") {
                SwitchRow(
                    title = "Wi-Fi 自动缓存",
                    subtitle = "播放时缓存当前歌曲与后续最多 3 首",
                    checked = settings.autoCache,
                    onCheckedChange = vm::setAutoCache,
                )
                SwitchRow(
                    title = "蜂窝网络下仅播放已缓存歌曲",
                    subtitle = "关闭后会按所选音质在线播放，可能消耗较多流量",
                    checked = settings.cellularWifiOnly,
                    onCheckedChange = vm::setCellularWifiOnly,
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            "已缓存 $cacheCount 首 · ${SettingsViewModel.formatBytes(cacheBytes)}",
                            style = MaterialTheme.typography.bodyMedium,
                            color = palette.ink,
                        )
                        Text(
                            "缓存保存在应用私有目录，不设容量上限，空间不足时暂停新增下载。",
                            style = MaterialTheme.typography.bodySmall,
                            color = palette.secondaryInk,
                        )
                    }
                    OutlinedButton(onClick = vm::clearCache) { Text("清除") }
                }
            }
        }

        item {
            SettingsCard(title = "歌词") {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Rounded.Subtitles, contentDescription = null, tint = palette.accent)
                    Spacer(Modifier.size(8.dp))
                    Text(
                        text = "全局偏移 %+.1f 秒".format(settings.lyricsOffsetMs / 1000f),
                        style = MaterialTheme.typography.bodyMedium,
                        color = palette.ink,
                        modifier = Modifier.weight(1f),
                    )
                    TextButton(onClick = { vm.setLyricsOffset(settings.lyricsOffsetMs - 500) }) {
                        Text("-0.5s")
                    }
                    TextButton(onClick = { vm.setLyricsOffset(settings.lyricsOffsetMs + 500) }) {
                        Text("+0.5s")
                    }
                    TextButton(onClick = { vm.setLyricsOffset(0) }) { Text("复位") }
                }
                Slider(
                    value = settings.lyricsOffsetMs.toFloat(),
                    onValueChange = { vm.setLyricsOffset(it.toLong()) },
                    valueRange = -5000f..5000f,
                    steps = 19,
                )
            }
        }

        item {
            SettingsCard(title = "关于") {
                Text(
                    "Sonar for Android ${BuildConfig.VERSION_NAME}",
                    style = MaterialTheme.typography.titleSmall,
                    color = palette.ink,
                )
                Text(
                    "原生 Kotlin + Jetpack Compose 音乐播放器。自有代码采用 GPL-3.0。",
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.secondaryInk,
                )
                Text(
                    "本项目不运营音乐后端，不随安装包分发音频文件。在线搜索、歌词与播放依赖第三方服务及账号权限；可用性与音质取决于服务返回结果。",
                    style = MaterialTheme.typography.bodySmall,
                    color = palette.tertiaryInk,
                )
            }
        }

        item { Spacer(Modifier.height(20.dp)) }
    }

    if (cookieDialog) {
        TextCredentialDialog(
            title = "网易云登录 Cookie",
            description = "粘贴 MUSIC_U=... 或整段 Cookie。只保存 MUSIC_U 的值。",
            singleLine = false,
            password = false,
            onDismiss = { cookieDialog = false },
            onSave = { value ->
                vm.saveCookie(value)
                cookieDialog = false
            },
            onClear = {
                vm.saveCookie(null)
                cookieDialog = false
            },
        )
    }
    if (keyDialog) {
        TextCredentialDialog(
            title = "ChKSz Key",
            description = "用于第三方歌曲搜索、歌词与播放回退。没有 Key 时可使用网易云直连。",
            singleLine = true,
            password = true,
            onDismiss = { keyDialog = false },
            onSave = { value ->
                vm.saveChkszKey(value)
                keyDialog = false
            },
            onClear = {
                vm.saveChkszKey(null)
                keyDialog = false
            },
        )
    }
}

@Composable
private fun SettingsCard(
    title: String,
    content: @Composable () -> Unit,
) {
    val palette = LocalSonarPalette.current
    Surface(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        color = palette.card,
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(title, style = MaterialTheme.typography.titleMedium, color = palette.ink)
            content()
        }
    }
}

@Composable
private fun CredentialRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    status: String,
    configured: Boolean,
    action: String,
    onAction: () -> Unit,
) {
    val palette = LocalSonarPalette.current
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = null, tint = palette.accent)
        Spacer(Modifier.size(10.dp))
        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.titleSmall, color = palette.ink)
            Text(
                status,
                style = MaterialTheme.typography.bodySmall,
                color = if (configured) palette.secondaryInk else palette.tertiaryInk,
            )
        }
        TextButton(onClick = onAction) { Text(action) }
    }
}

@Composable
private fun SwitchRow(
    title: String,
    subtitle: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    val palette = LocalSonarPalette.current
    Row(verticalAlignment = Alignment.CenterVertically) {
        Column(modifier = Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyMedium, color = palette.ink)
            Text(subtitle, style = MaterialTheme.typography.bodySmall, color = palette.secondaryInk)
        }
        Switch(checked = checked, onCheckedChange = onCheckedChange)
    }
}

@Composable
private fun TextCredentialDialog(
    title: String,
    description: String,
    singleLine: Boolean,
    password: Boolean,
    onDismiss: () -> Unit,
    onSave: (String) -> Unit,
    onClear: () -> Unit,
) {
    var value by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(description, style = MaterialTheme.typography.bodySmall)
                OutlinedTextField(
                    value = value,
                    onValueChange = { value = it },
                    singleLine = singleLine,
                    minLines = if (singleLine) 1 else 3,
                    visualTransformation = if (password) PasswordVisualTransformation() else androidx.compose.ui.text.input.VisualTransformation.None,
                    label = { Text("在此粘贴") },
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            Button(onClick = { onSave(value) }, enabled = value.isNotBlank()) { Text("保存") }
        },
        dismissButton = {
            Row {
                TextButton(onClick = onClear) { Text("清除") }
                TextButton(onClick = onDismiss) { Text("取消") }
            }
        },
    )
}
