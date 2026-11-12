@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package cn.bobochang.sonar.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Check
import androidx.compose.material.icons.rounded.ChevronRight
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.CloudDownload
import androidx.compose.material.icons.rounded.WorkspacePremium
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.Download
import androidx.compose.material.icons.rounded.Folder
import androidx.compose.material.icons.rounded.Key
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.SignalCellularOff
import androidx.compose.material.icons.rounded.Upload
import androidx.compose.material.icons.rounded.UploadFile
import androidx.compose.material.icons.rounded.GraphicEq
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import cn.bobochang.sonar.BuildConfig
import cn.bobochang.sonar.data.model.Quality
import cn.bobochang.sonar.data.model.title
import cn.bobochang.sonar.data.prefs.ThemeMode
import cn.bobochang.sonar.di.AppContainer
import cn.bobochang.sonar.ui.components.LocalToast
import cn.bobochang.sonar.ui.theme.LocalSonarPalette
import cn.bobochang.sonar.ui.viewmodel.SettingsViewModel
import kotlinx.coroutines.launch
import androidx.compose.runtime.rememberCoroutineScope

/** 对应 iOS `SettingsView`：从左侧滑出的设置抽屉。 */
@Composable
fun SettingsDrawer(
    container: AppContainer,
    onClose: () -> Unit,
    onExportBackup: () -> Unit,
    onImportBackup: () -> Unit,
    onImportFiles: () -> Unit,
    onImportFolder: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val vm: SettingsViewModel = viewModel(
        factory = viewModelFactory { initializer { SettingsViewModel(container) } },
    )
    val settings by vm.settings.collectAsStateWithLifecycle()
    val credentials by vm.credentials.collectAsStateWithLifecycle()
    val cacheCount by vm.cacheCount.collectAsStateWithLifecycle()
    val cacheBytes by vm.cacheBytes.collectAsStateWithLifecycle()
    val palette = LocalSonarPalette.current
    val toast = LocalToast.current
    val scope = rememberCoroutineScope()
    var cookieInput by remember { mutableStateOf("") }
    var showClearCache by remember { mutableStateOf(false) }
    var showQuality by remember { mutableStateOf(false) }
    var showKeyDialog by remember { mutableStateOf(false) }

    LaunchedEffect(Unit) {
        vm.messages.collect { toast.show(it) }
    }

    Column(
        modifier = modifier
            .fillMaxSize()
            .background(palette.background)
            .statusBarsPadding(),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 4.dp)
                .padding(top = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                modifier = Modifier.size(44.dp).clickable(onClick = onClose),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Rounded.Close,
                    contentDescription = "关闭设置",
                    tint = palette.ink,
                    modifier = Modifier.size(17.dp),
                )
            }
            Text(
                text = "设置",
                color = palette.ink,
                fontSize = 22.sp,
                fontWeight = FontWeight.Bold,
            )
            Spacer(Modifier.size(44.dp))
        }

        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 30.dp),
        ) {
            item(key = "appearance-title") { SectionTitle("外观") }
            item(key = "appearance") {
                Column(
                    modifier = Modifier.padding(horizontal = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    AppearancePicker(
                        selected = settings.themeMode,
                        onSelect = vm::setThemeMode,
                    )
                    SettingRow(
                        icon = Icons.Rounded.MusicNote,
                        title = "播放页封面取色",
                        subtitle = "用当前封面生成播放器背景",
                        trailing = {
                            ToggleSwitch(settings.coverAccentEnabled, onCheckedChange = { enabled ->
                                scope.launch { container.settings.setCoverAccentEnabled(enabled) }
                            })
                        },
                    )
                }
            }

            item(key = "account-title") { SectionTitle("网易云账号") }
            item(key = "cookie") {
                Column(
                    modifier = Modifier.padding(horizontal = 16.dp),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    TextField(
                        value = cookieInput,
                        onValueChange = { cookieInput = it },
                        modifier = Modifier.fillMaxWidth(),
                        placeholder = {
                            Text("粘贴 Cookie（MUSIC_U=…）", fontSize = 13.sp, color = palette.secondaryInk)
                        },
                        textStyle = androidx.compose.ui.text.TextStyle(
                            fontSize = 13.sp,
                            fontFamily = FontFamily.Monospace,
                            color = palette.ink,
                        ),
                        singleLine = true,
                        visualTransformation = PasswordVisualTransformation(),
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                        shape = RoundedCornerShape(10.dp),
                        colors = TextFieldDefaults.colors(
                            focusedContainerColor = palette.inputFill,
                            unfocusedContainerColor = palette.inputFill,
                            focusedIndicatorColor = Color.Transparent,
                            unfocusedIndicatorColor = Color.Transparent,
                            cursorColor = palette.accent,
                        ),
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                        DrawerButton(
                            title = if (credentials.checking) "验证中…" else "保存并验证",
                            filled = true,
                            enabled = !credentials.checking && cookieInput.isNotBlank(),
                            onClick = {
                                vm.saveCookie(cookieInput.trim())
                                vm.verifyAccount()
                                cookieInput = ""
                            },
                        )
                        DrawerButton(
                            title = "清除",
                            filled = false,
                            onClick = { vm.saveCookie(null) },
                        )
                    }
                    SettingRow(
                        icon = Icons.Rounded.WorkspacePremium,
                        title = "登录状态",
                        subtitle = when {
                            credentials.checking -> "正在校验…"
                            credentials.error != null -> credentials.error ?: "未登录"
                            credentials.accountName != null -> "已登录：${credentials.accountName} · VIP ${credentials.vipType}"
                            credentials.hasCookie -> "已配置 Cookie，可点按上方验证"
                            else -> "未配置；歌手、专辑搜索与高音质可能受限"
                        },
                        showDivider = false,
                    ) {
                        if (credentials.hasCookie) {
                            Icon(Icons.Rounded.Check, contentDescription = null, tint = palette.accent, modifier = Modifier.size(18.dp))
                        }
                    }
                    Text(
                        "Cookie 只保存在本机，使用 Android Keystore 加密，不写入备份或日志。",
                        color = palette.secondaryInk,
                        fontSize = 12.sp,
                        lineHeight = 17.sp,
                    )
                }
            }

            item(key = "chksz-title") { SectionTitle("第三方音源") }
            item(key = "chksz") {
                Column(modifier = Modifier.padding(horizontal = 16.dp)) {
                    SettingRow(
                        icon = Icons.Rounded.Key,
                        title = "ChKSz Key",
                        subtitle = if (credentials.hasChkszKey) "已配置，优先用于搜索与播放回退" else "未配置；网易云直连仍可使用",
                        showDivider = false,
                    ) {
                        Text(
                            "配置",
                            color = palette.accent,
                            fontSize = 14.sp,
                            fontWeight = FontWeight.Medium,
                            modifier = Modifier.clickable { showKeyDialog = true }.padding(6.dp),
                        )
                    }
                }
            }

            item(key = "playback-title") { SectionTitle("播放") }
            item(key = "playback") {
                Column(modifier = Modifier.padding(horizontal = 16.dp)) {
                    SettingRow(
                        icon = Icons.Rounded.GraphicEq,
                        title = "播放音质",
                        subtitle = settings.quality.title,
                        showDivider = false,
                        onClick = { showQuality = true },
                    ) { Chevron() }
                }
            }

            item(key = "cache-title") { SectionTitle("离线缓存") }
            item(key = "cache") {
                Column(modifier = Modifier.padding(horizontal = 16.dp)) {
                    SettingRow(
                        icon = Icons.Rounded.CloudDownload,
                        title = "自动缓存",
                        subtitle = "已缓存 $cacheCount 首 · ${SettingsViewModel.formatBytes(cacheBytes)}",
                    ) {
                        ToggleSwitch(settings.autoCache, onCheckedChange = vm::setAutoCache)
                    }
                    SettingRow(
                        icon = Icons.Rounded.SignalCellularOff,
                        title = "蜂窝网络下仅播放已缓存歌曲",
                        subtitle = "关闭后会按所选音质在线播放，可能消耗较多流量",
                    ) {
                        ToggleSwitch(settings.cellularWifiOnly, onCheckedChange = vm::setCellularWifiOnly)
                    }
                    SettingRow(
                        icon = Icons.Rounded.Delete,
                        title = "清除缓存",
                        subtitle = SettingsViewModel.formatBytes(cacheBytes),
                        showDivider = false,
                        onClick = { showClearCache = true },
                    ) { Chevron() }
                }
            }
            item(key = "cache-note") {
                Text(
                    "按所选音质缓存，不设容量上限。空间不足时暂停新增下载，已缓存歌曲保留。",
                    color = palette.secondaryInk,
                    fontSize = 12.sp,
                    lineHeight = 17.sp,
                    modifier = Modifier.padding(horizontal = 16.dp).padding(top = 8.dp),
                )
            }

            item(key = "playlist-title") { SectionTitle("歌单") }
            item(key = "backup") {
                Column(modifier = Modifier.padding(horizontal = 16.dp)) {
                    SettingRow(
                        icon = Icons.Rounded.Upload,
                        title = "导出备份",
                        subtitle = "将收藏歌曲保存到文件",
                        onClick = onExportBackup,
                    ) { Chevron() }
                    SettingRow(
                        icon = Icons.Rounded.Download,
                        title = "导入备份",
                        subtitle = "合并备份中的歌曲，保留现有收藏与歌单",
                        onClick = onImportBackup,
                    ) { Chevron() }
                    SettingRow(
                        icon = Icons.Rounded.UploadFile,
                        title = "导入本地文件",
                        subtitle = "选择音频文件加入资料库",
                        onClick = onImportFiles,
                    ) { Chevron() }
                    SettingRow(
                        icon = Icons.Rounded.Folder,
                        title = "导入文件夹",
                        subtitle = "扫描文件夹内的音频与同名歌词",
                        showDivider = false,
                        onClick = onImportFolder,
                    ) { Chevron() }
                }
            }

            item(key = "about-title") { SectionTitle("关于") }
            item(key = "about") {
                Column(modifier = Modifier.padding(horizontal = 16.dp)) {
                    SettingRow(
                        icon = Icons.Rounded.MusicNote,
                        title = "Sonar",
                        subtitle = "Android ${BuildConfig.VERSION_NAME}",
                        showDivider = false,
                    ) {}
                }
            }
            item(key = "about-note") {
                Text(
                    "原生 Kotlin + Jetpack Compose 音乐播放器。本项目不运营音乐后端，不随安装包分发音频文件。",
                    color = palette.tertiaryInk,
                    fontSize = 12.sp,
                    lineHeight = 17.sp,
                    modifier = Modifier.padding(horizontal = 16.dp).padding(top = 10.dp),
                )
            }
        }
    }

    if (showClearCache) {
        AlertDialog(
            onDismissRequest = { showClearCache = false },
            title = { Text("清除全部缓存？") },
            text = { Text("已缓存的歌曲会从本机删除，再次播放时需要重新下载。") },
            confirmButton = {
                TextButton(onClick = {
                    showClearCache = false
                    vm.clearCache()
                }) { Text("清除缓存", color = palette.error) }
            },
            dismissButton = {
                TextButton(onClick = { showClearCache = false }) { Text("取消") }
            },
        )
    }

    if (showQuality) {
        ModalBottomSheet(
            onDismissRequest = { showQuality = false },
            containerColor = palette.background,
        ) {
            QualityPreferenceSheet(
                selected = settings.quality,
                onSelect = { quality ->
                    showQuality = false
                    vm.setQuality(quality)
                    val current = container.playerConnection.state.value.track
                    if (current != null) {
                        container.playerConnection.reloadAtQuality(current, quality)
                    }
                    toast.show("已切换到 ${quality.title}")
                },
            )
        }
    }

    if (showKeyDialog) {
        var value by remember { mutableStateOf("") }
        AlertDialog(
            onDismissRequest = { showKeyDialog = false },
            title = { Text("ChKSz Key") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        "用于第三方歌曲搜索、歌词与播放回退。没有 Key 时可使用网易云直连。",
                        color = palette.secondaryInk,
                        fontSize = 13.sp,
                    )
                    TextField(
                        value = value,
                        onValueChange = { value = it },
                        modifier = Modifier.fillMaxWidth(),
                        placeholder = { Text("粘贴 Key") },
                        singleLine = true,
                        visualTransformation = PasswordVisualTransformation(),
                        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    )
                }
            },
            confirmButton = {
                TextButton(
                    enabled = value.isNotBlank(),
                    onClick = {
                        vm.saveChkszKey(value.trim())
                        showKeyDialog = false
                    },
                ) { Text("保存") }
            },
            dismissButton = {
                Row {
                    TextButton(onClick = {
                        vm.saveChkszKey(null)
                        showKeyDialog = false
                    }) { Text("清除") }
                    TextButton(onClick = { showKeyDialog = false }) { Text("取消") }
                }
            },
        )
    }
}

@Composable
private fun SectionTitle(title: String) {
    val palette = LocalSonarPalette.current
    Text(
        text = title,
        color = palette.secondaryInk,
        fontSize = 13.sp,
        fontWeight = FontWeight.SemiBold,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .padding(top = 22.dp, bottom = 10.dp),
    )
}

@Composable
private fun SettingRow(
    icon: ImageVector,
    title: String,
    subtitle: String,
    showDivider: Boolean = true,
    onClick: (() -> Unit)? = null,
    trailing: @Composable () -> Unit,
) {
    val palette = LocalSonarPalette.current
    Column(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 58.dp)
                .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = palette.accent,
                modifier = Modifier.size(18.dp),
            )
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(
                    text = title,
                    color = palette.ink,
                    fontSize = 16.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = subtitle,
                    color = palette.secondaryInk,
                    fontSize = 12.sp,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            trailing()
        }
        if (showDivider) {
            HorizontalDivider(
                color = palette.divider,
                thickness = 0.5.dp,
                modifier = Modifier.padding(start = 42.dp),
            )
        }
    }
}

@Composable
private fun ToggleSwitch(checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    val palette = LocalSonarPalette.current
    Switch(
        checked = checked,
        onCheckedChange = onCheckedChange,
        colors = SwitchDefaults.colors(
            checkedThumbColor = palette.onAccent,
            checkedTrackColor = palette.accent,
            uncheckedThumbColor = palette.card,
            uncheckedTrackColor = palette.ink.copy(alpha = 0.16f),
            uncheckedBorderColor = Color.Transparent,
        ),
    )
}

@Composable
private fun Chevron() {
    Icon(
        Icons.Rounded.ChevronRight,
        contentDescription = null,
        tint = LocalSonarPalette.current.outline,
        modifier = Modifier.size(16.dp),
    )
}

@Composable
private fun AppearancePicker(selected: ThemeMode, onSelect: (ThemeMode) -> Unit) {
    val palette = LocalSonarPalette.current
    val modes = listOf(
        ThemeMode.LIGHT to "浅色",
        ThemeMode.DARK to "深色",
        ThemeMode.SYSTEM to "跟随",
    )
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(palette.ink.copy(alpha = 0.06f), RoundedCornerShape(9.dp))
            .padding(2.dp),
    ) {
        modes.forEach { (mode, label) ->
            val active = selected == mode
            Box(
                modifier = Modifier
                    .weight(1f)
                    .height(32.dp)
                    .background(if (active) palette.card else Color.Transparent, RoundedCornerShape(8.dp))
                    .clickable { onSelect(mode) },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    text = label,
                    color = if (active) palette.ink else palette.secondaryInk,
                    fontSize = 13.sp,
                    fontWeight = if (active) FontWeight.SemiBold else FontWeight.Normal,
                )
            }
        }
    }
}

@Composable
private fun DrawerButton(
    title: String,
    filled: Boolean,
    enabled: Boolean = true,
    onClick: () -> Unit,
) {
    val palette = LocalSonarPalette.current
    Box(
        modifier = Modifier
            .heightIn(min = 40.dp)
            .background(
                if (filled) palette.accent.copy(alpha = if (enabled) 1f else 0.4f)
                else Color.Transparent,
                RoundedCornerShape(10.dp),
            )
            .then(
                if (filled) Modifier else Modifier.border(1.dp, palette.divider, RoundedCornerShape(10.dp)),
            )
            .clickable(enabled = enabled, onClick = onClick)
            .padding(horizontal = 14.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = title,
            color = if (filled) palette.onAccent else palette.secondaryInk,
            fontSize = 14.sp,
            fontWeight = FontWeight.Medium,
        )
    }
}

@Composable
private fun QualityPreferenceSheet(selected: Quality, onSelect: (Quality) -> Unit) {
    val palette = LocalSonarPalette.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Text(
            "播放音质",
            color = palette.ink,
            fontSize = 22.sp,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.padding(start = 24.dp, top = 14.dp, bottom = 4.dp),
        )
        Text(
            "从母带开始逐级回退，对下一次播放生效。",
            color = palette.secondaryInk,
            fontSize = 12.sp,
            modifier = Modifier.padding(horizontal = 24.dp).padding(bottom = 10.dp),
        )
        Quality.descending.forEach { quality ->
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onSelect(quality) }
                    .padding(horizontal = 24.dp)
                    .heightIn(min = 54.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(quality.title, color = palette.ink, fontSize = 15.sp, fontWeight = FontWeight.Medium)
                    Text(quality.displayName, color = palette.secondaryInk, fontSize = 12.sp)
                }
                if (selected == quality) {
                    Icon(Icons.Rounded.Check, contentDescription = null, tint = palette.accent, modifier = Modifier.size(20.dp))
                }
            }
        }
    }
}
