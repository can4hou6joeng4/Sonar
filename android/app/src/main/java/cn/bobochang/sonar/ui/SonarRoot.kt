@file:OptIn(
    androidx.compose.foundation.ExperimentalFoundationApi::class,
    androidx.compose.material3.ExperimentalMaterial3Api::class,
)

package cn.bobochang.sonar.ui

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.LibraryMusic
import androidx.compose.material.icons.outlined.MusicNote
import androidx.compose.material.icons.rounded.LibraryMusic
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.PlaylistAdd
import androidx.compose.material.icons.rounded.PlaylistPlay
import androidx.compose.material.icons.rounded.QueueMusic
import androidx.compose.material.icons.rounded.Share
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.changedToUpIgnoreConsumed
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import cn.bobochang.sonar.data.library.BackupTarget
import cn.bobochang.sonar.data.library.PlaylistBackupCodec
import cn.bobochang.sonar.data.model.AlbumSummary
import cn.bobochang.sonar.data.model.ArtistSummary
import cn.bobochang.sonar.data.model.MusicSource
import cn.bobochang.sonar.data.model.PlaylistSummary
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.data.prefs.SonarSettings
import cn.bobochang.sonar.di.AppContainer
import cn.bobochang.sonar.playback.PlayerUiState
import cn.bobochang.sonar.ui.components.LocalToast
import cn.bobochang.sonar.ui.components.NcmMiniPlayer
import cn.bobochang.sonar.ui.components.PlaylistPickerSheet
import cn.bobochang.sonar.ui.components.ProvideToast
import cn.bobochang.sonar.ui.components.SongAction
import cn.bobochang.sonar.ui.components.SongActionsSheet
import cn.bobochang.sonar.ui.components.ToastController
import cn.bobochang.sonar.ui.components.ToastOverlay
import cn.bobochang.sonar.ui.theme.circleIconPress
import cn.bobochang.sonar.ui.player.PlayerScreen
import cn.bobochang.sonar.ui.player.PlayerSurface
import cn.bobochang.sonar.ui.screens.AlbumDetailScreen
import cn.bobochang.sonar.ui.screens.ArtistDetailScreen
import cn.bobochang.sonar.ui.screens.HomeScreen
import cn.bobochang.sonar.ui.screens.LibraryScreen
import cn.bobochang.sonar.ui.screens.PlaylistDetailScreen
import cn.bobochang.sonar.ui.screens.RemotePlaylistScreen
import cn.bobochang.sonar.ui.theme.AppMotion
import cn.bobochang.sonar.ui.theme.LocalReduceMotion
import cn.bobochang.sonar.ui.theme.LocalSonarPalette
import cn.bobochang.sonar.ui.theme.SonarTheme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlin.math.abs
import kotlin.math.max

private enum class RootTab { HOME, LIBRARY }

private sealed interface RootRoute {
    data object Favorites : RootRoute
    data class Playlist(val id: String) : RootRoute
    data class RemotePlaylist(val playlist: PlaylistSummary) : RootRoute
    data class Artist(val artist: ArtistSummary) : RootRoute
    data class Album(val album: AlbumSummary) : RootRoute
}

/** iOS `SpotlightLayout`。 */
private object ShellLayout {
    val navigationHeight = 50.dp
    val miniPlayerHeight = 62.dp
    val chromeSpacing = 8.dp
    val bottomPadding = 6.dp
    val horizontalPadding = 18.dp
}

private object DrawerMetrics {
    const val widthRatio = 0.84f
    val minimumWidth = 280.dp
    val maximumWidth = 340.dp
    const val completionRatio = 0.35f
    const val predictedCompletionRatio = 0.55f
    val activationWidth = 26.dp
}

private object PlayerPullMetrics {
    val dismissDistance = 140.dp
    const val dismissVelocity = 550f
    const val upwardResistance = 0.28f
    val maximumUpwardTravel = 46.dp
    val feedbackDistance = 560.dp
}

@Composable
fun SonarRoot(container: AppContainer) {
    val settings by container.settings.settings.collectAsStateWithLifecycle(initialValue = SonarSettings())
    SonarTheme(themeMode = settings.themeMode) {
        val reduceMotion = rememberReduceMotion()
        CompositionLocalProvider(LocalReduceMotion provides reduceMotion) {
            RootContent(container = container, settings = settings)
        }
    }
}

@Composable
private fun RootContent(container: AppContainer, settings: SonarSettings) {
    val palette = LocalSonarPalette.current
    val context = LocalContext.current
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    val toast = remember { ToastController(scope) }
    val playerState by container.playerConnection.state.collectAsStateWithLifecycle()
    val statusTop = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    val navBottom = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
    val density = LocalDensity.current

    var tab by rememberSaveable { mutableStateOf(RootTab.HOME) }
    var routeStack by remember { mutableStateOf<List<RootRoute>>(emptyList()) }
    var showWelcome by remember { mutableStateOf(true) }
    var searchVisible by remember { mutableStateOf(false) }
    var actionTrack by remember { mutableStateOf<Track?>(null) }
    var pickerTrack by remember { mutableStateOf<Track?>(null) }
    var playerOpen by remember { mutableStateOf(false) }
    var playerSurface by remember { mutableStateOf(PlayerSurface.ARTWORK) }
    var playerTranslation by remember { mutableFloatStateOf(0f) }
    val playerPull = remember { androidx.compose.animation.core.Animatable(0f) }

    var drawerOpen by remember { mutableStateOf(false) }
    var drawerFraction by remember { mutableFloatStateOf(0f) }
    var drawerAnimation by remember { mutableStateOf<Job?>(null) }

    val activity = remember(context) { context.findActivity() }
    val lightSystemBars = showWelcome || playerOpen || palette.isDark
    LaunchedEffect(lightSystemBars) {
        val window = activity?.window ?: return@LaunchedEffect
        WindowCompat.getInsetsController(window, view).apply {
            isAppearanceLightStatusBars = !lightSystemBars
            isAppearanceLightNavigationBars = !lightSystemBars
        }
    }

    fun closeDrawerImmediate() {
        drawerAnimation?.cancel()
        drawerOpen = false
        drawerFraction = 0f
    }

    fun openSearch() {
        closeDrawerImmediate()
        searchVisible = true
    }

    fun animateDrawerTo(target: Float, open: Boolean) {
        drawerAnimation?.cancel()
        drawerAnimation = scope.launch {
            animate(drawerFraction, target, animationSpec = tween(AppMotion.MEDIUM, easing = AppMotion.emphasized)) { value, _ ->
                drawerFraction = value
            }
            drawerFraction = target
            drawerOpen = open
        }
    }

    fun openDrawer() {
        if (playerOpen || searchVisible) return
        drawerAnimation?.cancel()
        drawerOpen = true
        animateDrawerTo(1f, true)
    }

    fun closeDrawer() {
        if (!drawerOpen) return
        animateDrawerTo(0f, false)
    }

    fun openPlayer(surface: PlayerSurface) {
        searchVisible = false
        closeDrawerImmediate()
        playerSurface = surface
        playerTranslation = 0f
        playerOpen = true
        scope.launch {
            playerPull.snapTo(0f)
            androidx.compose.runtime.withFrameNanos { }
            playerPull.animateTo(1f, tween(AppMotion.LONG, easing = AppMotion.playerPull))
        }
    }

    fun closePlayer() {
        scope.launch {
            playerPull.animateTo(0f, tween(AppMotion.LONG, easing = AppMotion.playerPull))
            playerOpen = false
            playerTranslation = 0f
            playerSurface = PlayerSurface.ARTWORK
        }
    }

    fun settlePlayer(velocityY: Float) {
        val distancePx = with(density) { PlayerPullMetrics.dismissDistance.toPx() }
        if (playerTranslation > 0f &&
            (velocityY > PlayerPullMetrics.dismissVelocity || playerTranslation > distancePx)
        ) {
            closePlayer()
        } else {
            val start = playerTranslation
            scope.launch {
                animate(start, 0f, animationSpec = tween(AppMotion.LONG, easing = AppMotion.playerPull)) { value, _ ->
                    playerTranslation = value
                }
                playerTranslation = 0f
            }
        }
    }

    fun push(route: RootRoute) {
        routeStack = routeStack + route
    }

    fun pop() {
        if (routeStack.isNotEmpty()) routeStack = routeStack.dropLast(1)
    }

    // Android 独有的本地导入 / 备份导入导出入口。
    val importFilesLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenMultipleDocuments(),
    ) { uris ->
        if (uris.isEmpty()) return@rememberLauncherForActivityResult
        uris.forEach { uri ->
            runCatching {
                context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
        }
        scope.launch {
            val tracks = runCatching { container.localImporter.importUris(uris) }.getOrDefault(emptyList())
            tracks.forEach { container.library.addFavorite(it) }
            toast.show(
                if (tracks.isEmpty()) "没有读到可播放的本地音频" else "已导入 ${tracks.size} 首本地歌曲",
            )
        }
    }

    val importFolderLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocumentTree(),
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        runCatching {
            context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        scope.launch {
            val tracks = runCatching { container.localImporter.importTree(uri) }.getOrDefault(emptyList())
            tracks.forEach { container.library.addFavorite(it) }
            toast.show(
                if (tracks.isEmpty()) "文件夹中没有可导入的音频" else "已导入 ${tracks.size} 首本地歌曲",
            )
        }
    }

    val exportBackupLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.CreateDocument("application/json"),
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            val json = runCatching { container.library.exportFavorites() }.getOrNull()
            if (json == null) {
                toast.show("导出未完成，请稍后重试")
                return@launch
            }
            val ok = withContext(Dispatchers.IO) {
                runCatching {
                    context.contentResolver.openOutputStream(uri)?.use { output ->
                        output.write(json.toByteArray())
                    } != null
                }.getOrDefault(false)
            }
            toast.show(if (ok) "已导出收藏备份" else "导出未完成，请选择可写入的位置")
        }
    }

    val importBackupLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument(),
    ) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            val bytes = withContext(Dispatchers.IO) {
                runCatching {
                    context.contentResolver.openInputStream(uri)?.use { input ->
                        val buffer = ByteArray(PlaylistBackupCodec.MAX_BYTES + 1)
                        var read = 0
                        while (read < buffer.size) {
                            val count = input.read(buffer, read, buffer.size - read)
                            if (count <= 0) break
                            read += count
                        }
                        buffer.copyOf(read)
                    }
                }.getOrNull()
            }
            when {
                bytes == null -> toast.show("暂时无法打开所选文件")
                bytes.size > PlaylistBackupCodec.MAX_BYTES -> toast.show("备份文件超过 10 MB，未导入")
                else -> {
                    val result = runCatching {
                        container.library.importBackup(bytes, BackupTarget.Favorites)
                    }.getOrNull()
                    toast.show(
                        if (result == null) "导入未完成，请选择有效的 Sonar 歌单备份"
                        else "已添加 ${result.inserted} 首，跳过 ${result.skipped} 首重复歌曲",
                    )
                }
            }
        }
    }

    val notificationPermissionLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission(),
    ) { }
    var notificationAsked by remember { mutableStateOf(false) }

    // 通知权限只在首次真正开始播放时请求，避免系统弹窗打断欢迎页。
    LaunchedEffect(playerState.hasTrack) {
        if (!playerState.hasTrack || notificationAsked || Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return@LaunchedEffect
        }
        val granted = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (!granted) {
            notificationAsked = true
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    LaunchedEffect(playerState.error) {
        playerState.error?.let { toast.show("播放失败：$it") }
    }

    // 系统返回：先收最上层的浮层，再退详情页，最后让 Activity 处理。
    BackHandler(enabled = showWelcome) { }
    BackHandler(enabled = !showWelcome && playerOpen) { closePlayer() }
    BackHandler(enabled = !showWelcome && !playerOpen && searchVisible) {
        searchVisible = false
    }
    BackHandler(enabled = !showWelcome && !playerOpen && !searchVisible && drawerOpen) {
        closeDrawer()
    }
    BackHandler(
        enabled = !showWelcome && !playerOpen && !searchVisible && !drawerOpen && routeStack.isNotEmpty(),
    ) { pop() }
    BackHandler(
        enabled = !showWelcome && !playerOpen && !searchVisible && !drawerOpen &&
            routeStack.isEmpty() && tab == RootTab.LIBRARY,
    ) { tab = RootTab.HOME }

    ProvideToast(toast) {
        BoxWithConstraints(Modifier.fillMaxSize().background(palette.background)) {
            val heightPx = with(density) { maxHeight.toPx() }
            val statusPx = with(density) { statusTop.toPx() }
            val navPx = with(density) { navBottom.toPx() }
            val playerTravel = heightPx + statusPx + navPx
            val feedbackPx = with(density) { PlayerPullMetrics.feedbackDistance.toPx() }.coerceAtLeast(1f)
            val upwardLimitPx = with(density) { PlayerPullMetrics.maximumUpwardTravel.toPx() }

            val drawerWidth = minOf(
                maxOf(maxWidth * DrawerMetrics.widthRatio, DrawerMetrics.minimumWidth),
                DrawerMetrics.maximumWidth,
            ).coerceAtMost(maxWidth)
            val drawerWidthPx = with(density) { drawerWidth.toPx() }

            val hasTrack = playerState.hasTrack
            val chromeHeight = ShellLayout.navigationHeight + ShellLayout.bottomPadding + navBottom +
                if (hasTrack) ShellLayout.miniPlayerHeight + ShellLayout.chromeSpacing else 0.dp
            val contentBottom = chromeHeight + 12.dp

            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .edgeDrawerGesture(
                        enabled = !showWelcome && !searchVisible && !playerOpen && !drawerOpen,
                        edgeWidthPx = with(density) { DrawerMetrics.activationWidth.toPx() },
                        onDragStart = {
                            drawerAnimation?.cancel()
                            drawerOpen = true
                        },
                        onDrag = { translation ->
                            drawerFraction = (translation / drawerWidthPx).coerceIn(0f, 1f)
                        },
                        onDragEnd = { translation, velocity ->
                            val predicted = (translation + velocity * 0.12f) / drawerWidthPx
                            val shouldOpen = translation / drawerWidthPx > DrawerMetrics.completionRatio ||
                                predicted > DrawerMetrics.predictedCompletionRatio
                            if (shouldOpen) animateDrawerTo(1f, true) else animateDrawerTo(0f, false)
                        },
                    ),
            ) {
                val route = routeStack.lastOrNull()
                if (route == null) {
                    when (tab) {
                        RootTab.HOME -> HomeScreen(
                            container = container,
                            playerState = playerState,
                            bottomPadding = contentBottom,
                            onOpenSearch = ::openSearch,
                            onOpenSettings = ::openDrawer,
                            onShowCollection = {
                                tab = RootTab.LIBRARY
                                routeStack = emptyList()
                            },
                            onSongAction = { actionTrack = it },
                        )

                        RootTab.LIBRARY -> LibraryScreen(
                            container = container,
                            playerState = playerState,
                            bottomPadding = contentBottom,
                            onOpenSettings = ::openDrawer,
                            onOpenPlaylist = { id -> push(RootRoute.Playlist(id)) },
                            onImportFiles = { importFilesLauncher.launch(arrayOf("audio/*")) },
                            onImportFolder = { importFolderLauncher.launch(null) },
                            onSongAction = { actionTrack = it },
                        )
                    }
                } else {
                    when (route) {
                        RootRoute.Favorites -> PlaylistDetailScreen(
                            container = container,
                            playerState = playerState,
                            playlistId = null,
                            bottomPadding = contentBottom,
                            onBack = ::pop,
                            onSongAction = { actionTrack = it },
                        )

                        is RootRoute.Playlist -> PlaylistDetailScreen(
                            container = container,
                            playerState = playerState,
                            playlistId = route.id,
                            bottomPadding = contentBottom,
                            onBack = ::pop,
                            onSongAction = { actionTrack = it },
                        )

                        is RootRoute.RemotePlaylist -> RemotePlaylistScreen(
                            container = container,
                            playerState = playerState,
                            playlist = route.playlist,
                            bottomPadding = contentBottom,
                            onBack = ::pop,
                            onSongAction = { actionTrack = it },
                        )

                        is RootRoute.Artist -> ArtistDetailScreen(
                            container = container,
                            playerState = playerState,
                            artist = route.artist,
                            bottomPadding = contentBottom,
                            onBack = ::pop,
                            onSongAction = { actionTrack = it },
                            onOpenAlbum = { album -> push(RootRoute.Album(album)) },
                        )

                        is RootRoute.Album -> AlbumDetailScreen(
                            container = container,
                            playerState = playerState,
                            album = route.album,
                            bottomPadding = contentBottom,
                            onBack = ::pop,
                            onSongAction = { actionTrack = it },
                        )
                    }
                }
            }

            // 底部 chrome：mini player + 两个图标 Tab。
            if (!showWelcome) {
                BottomChrome(
                    tab = tab,
                    playerState = playerState,
                    navBottom = navBottom,
                    playerPull = playerPull.value,
                    onSelectTab = { value ->
                        if (tab != value) {
                            tab = value
                            routeStack = emptyList()
                        }
                    },
                    onOpenPlayer = { openPlayer(PlayerSurface.ARTWORK) },
                    onOpenQueue = { openPlayer(PlayerSurface.QUEUE) },
                    onPlayPause = {
                        if (playerState.error != null) container.playerConnection.retry()
                        else container.playerConnection.toggle()
                    },
                    onNext = { container.playerConnection.next() },
                    onPrevious = { container.playerConnection.previous() },
                    modifier = Modifier.align(Alignment.BottomCenter),
                )
            }

            if (playerOpen) {
                val progress = (playerTranslation / feedbackPx).coerceIn(0f, 1f)
                val scale = 1f - progress * 0.05f
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .graphicsLayer {
                            translationY = (1f - playerPull.value) * playerTravel + playerTranslation
                            scaleX = scale
                            scaleY = scale
                            alpha = 1f - progress * 0.28f
                        },
                ) {
                    PlayerScreen(
                        context = context,
                        container = container,
                        settings = settings,
                        state = playerState,
                        surface = playerSurface,
                        onSurfaceChange = { playerSurface = it },
                        onClose = ::closePlayer,
                        onDismissDrag = { amount ->
                            val next = playerTranslation + amount
                            playerTranslation = if (next < 0f) {
                                max(next * PlayerPullMetrics.upwardResistance, -upwardLimitPx)
                            } else {
                                next
                            }
                        },
                        onDismissRelease = { velocity -> settlePlayer(velocity) },
                    )
                }
            }

            AnimatedVisibility(
                visible = searchVisible,
                enter = fadeIn(tween(AppMotion.SHORT, easing = AppMotion.emphasized)),
                exit = fadeOut(tween(AppMotion.SHORT)),
            ) {
                SearchOverlay(
                    container = container,
                    playerState = playerState,
                    onClose = { searchVisible = false },
                    onOpenArtist = {
                        searchVisible = false
                        push(RootRoute.Artist(it))
                    },
                    onOpenAlbum = {
                        searchVisible = false
                        push(RootRoute.Album(it))
                    },
                    onOpenPlaylist = {
                        searchVisible = false
                        push(RootRoute.RemotePlaylist(it))
                    },
                    onSongAction = { actionTrack = it },
                )
            }

            if (drawerOpen || drawerFraction > 0.001f) {
                Box(Modifier.fillMaxSize()) {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .background(Color.Black.copy(alpha = 0.42f * drawerFraction))
                            .clickable(
                                interactionSource = remember { MutableInteractionSource() },
                                indication = null,
                                onClick = ::closeDrawer,
                            ),
                    )
                    SettingsDrawer(
                        container = container,
                        onClose = ::closeDrawer,
                        onExportBackup = { exportBackupLauncher.launch("Sonar-歌单备份.json") },
                        onImportBackup = {
                            importBackupLauncher.launch(
                                arrayOf("application/json", "text/plain", "application/octet-stream"),
                            )
                        },
                        onImportFiles = { importFilesLauncher.launch(arrayOf("audio/*")) },
                        onImportFolder = { importFolderLauncher.launch(null) },
                        modifier = Modifier
                            .width(drawerWidth)
                            .fillMaxSize()
                            .graphicsLayer {
                                translationX = (drawerFraction - 1f) * drawerWidthPx
                            }
                            .shadow(18.dp)
                            .drawerPanelDrag(
                                onDragStart = { drawerAnimation?.cancel() },
                                onDrag = { translation ->
                                    drawerFraction = (1f + translation / drawerWidthPx).coerceIn(0f, 1f)
                                },
                                onDragEnd = { translation, velocity ->
                                    val predicted = 1f +
                                        (translation + velocity * 0.12f) / drawerWidthPx
                                    val shouldClose = drawerFraction < 0.65f || predicted < 0.45f
                                    if (shouldClose) animateDrawerTo(0f, false) else animateDrawerTo(1f, true)
                                },
                            ),
                    )
                }
            }

            if (showWelcome) {
                WelcomeView(container = container, onComplete = { showWelcome = false })
            }

            ToastOverlay(
                controller = toast,
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(bottom = 96.dp + navBottom),
            )
        }
    }

    actionTrack?.let { track ->
        ModalBottomSheet(
            onDismissRequest = { actionTrack = null },
            containerColor = palette.background,
            dragHandle = null,
        ) {
            val isCollected by container.library.observeIsFavorite(track.musicId)
                .collectAsState(initial = false)
            SongActionsSheet(
                track = track,
                isCollected = isCollected,
                actions = listOf(
                    SongAction(
                        title = "下一首播放",
                        icon = Icons.Rounded.PlaylistPlay,
                        enabled = track.source.isEnabled,
                        perform = {
                            scope.launch {
                                container.playerConnection.addNext(track, settings.quality)
                                toast.show("已设为下一首播放")
                            }
                        },
                    ),
                    SongAction(
                        title = "加入待播放",
                        icon = Icons.Rounded.QueueMusic,
                        enabled = track.source.isEnabled,
                        perform = {
                            scope.launch {
                                container.playerConnection.enqueue(track, settings.quality)
                                toast.show("已加入待播放")
                            }
                        },
                    ),
                    SongAction(
                        title = "收藏到歌单",
                        icon = Icons.Rounded.PlaylistAdd,
                        perform = {
                            scope.launch {
                                delay(220)
                                pickerTrack = track
                            }
                        },
                    ),
                    SongAction(
                        title = "分享歌曲",
                        icon = Icons.Rounded.Share,
                        perform = { shareTrack(context, track) },
                    ),
                ),
                onToggleCollection = {
                    scope.launch {
                        val added = container.library.toggleFavorite(track)
                        toast.show(if (added) "已收藏" else "已取消收藏")
                    }
                },
                onCancel = { actionTrack = null },
            )
        }
    }

    pickerTrack?.let { track ->
        val playlists by container.library.observePlaylists().collectAsState(initial = emptyList())
        val isCollected by container.library.observeIsFavorite(track.musicId).collectAsState(initial = false)
        ModalBottomSheet(
            onDismissRequest = { pickerTrack = null },
            containerColor = palette.background,
            dragHandle = null,
        ) {
            PlaylistPickerSheet(
                playlists = playlists,
                isFavorite = isCollected,
                onToggleFavorite = {
                    scope.launch {
                        val added = container.library.toggleFavorite(track)
                        toast.show(if (added) "已收藏" else "已取消收藏")
                    }
                },
                onPickPlaylist = { playlist ->
                    pickerTrack = null
                    scope.launch {
                        val count = container.library.addTracksToPlaylist(playlist.id, listOf(track))
                        toast.show(
                            if (count > 0) "已添加到「${playlist.name}」" else "歌曲已在「${playlist.name}」中",
                        )
                    }
                },
                onCancel = { pickerTrack = null },
            )
        }
    }
}

@Composable
private fun BottomChrome(
    tab: RootTab,
    playerState: PlayerUiState,
    navBottom: androidx.compose.ui.unit.Dp,
    playerPull: Float,
    onSelectTab: (RootTab) -> Unit,
    onOpenPlayer: () -> Unit,
    onOpenQueue: () -> Unit,
    onPlayPause: () -> Unit,
    onNext: () -> Unit,
    onPrevious: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val palette = LocalSonarPalette.current
    Column(
        modifier = modifier
            .fillMaxWidth()
            .graphicsLayer { alpha = 1f - playerPull }
            .background(
                Brush.verticalGradient(
                    0f to Color.Transparent,
                    0.30f to palette.background.copy(alpha = 0.88f),
                    0.52f to palette.background,
                    1f to palette.background,
                ),
            )
            .padding(top = 20.dp)
            .padding(horizontal = ShellLayout.horizontalPadding)
            .padding(bottom = navBottom + ShellLayout.bottomPadding),
        verticalArrangement = Arrangement.spacedBy(ShellLayout.chromeSpacing),
    ) {
        AnimatedVisibility(
            visible = playerState.hasTrack,
            enter = slideInVertically(tween(AppMotion.MEDIUM, easing = AppMotion.emphasizedDecelerate)) { it } +
                fadeIn(tween(AppMotion.MEDIUM)),
            exit = slideOutVertically(tween(AppMotion.MEDIUM)) { it } + fadeOut(tween(AppMotion.SHORT)),
        ) {
            NcmMiniPlayer(
                state = playerState,
                onOpen = onOpenPlayer,
                onOpenQueue = onOpenQueue,
                onPlayPause = onPlayPause,
                onNext = onNext,
                onPrevious = onPrevious,
            )
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(ShellLayout.navigationHeight),
        ) {
            TabButton(
                icon = if (tab == RootTab.HOME) Icons.Rounded.MusicNote else Icons.Outlined.MusicNote,
                label = "首页",
                selected = tab == RootTab.HOME,
                modifier = Modifier.weight(1f),
                onClick = { onSelectTab(RootTab.HOME) },
            )
            TabButton(
                icon = if (tab == RootTab.LIBRARY) Icons.Rounded.LibraryMusic else Icons.Outlined.LibraryMusic,
                label = "资料库",
                selected = tab == RootTab.LIBRARY,
                modifier = Modifier.weight(1f),
                onClick = { onSelectTab(RootTab.LIBRARY) },
            )
        }
    }
}

@Composable
private fun TabButton(
    icon: ImageVector,
    label: String,
    selected: Boolean,
    modifier: Modifier,
    onClick: () -> Unit,
) {
    val palette = LocalSonarPalette.current
    val interaction = remember { MutableInteractionSource() }
    Box(
        modifier = modifier
            .height(50.dp)
            .then(circleIconPress(interaction, 42.dp)),
        contentAlignment = Alignment.Center,
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .clip(CircleShape)
                .clickable(interactionSource = interaction, indication = null, onClick = onClick),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = label,
                tint = if (selected) palette.ink else palette.secondaryInk.copy(alpha = 0.75f),
                modifier = Modifier.size(22.dp),
            )
        }
    }
}

private fun shareTrack(context: Context, track: Track) {
    val link = if (track.source == MusicSource.WY) {
        "https://music.163.com/song?id=${track.songmid}"
    } else {
        ""
    }
    val text = buildList {
        add(track.title)
        if (track.artist.isNotBlank()) add(track.artist)
        if (link.isNotEmpty()) add(link)
    }.joinToString(" - ")
    val intent = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_TEXT, text)
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    runCatching {
        context.startActivity(Intent.createChooser(intent, "分享歌曲").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}

/** 让抽屉面板本身支持左滑关闭，同时不阻挡设置列表的纵向滚动。 */
private fun Modifier.drawerPanelDrag(
    onDragStart: () -> Unit,
    onDrag: (translation: Float) -> Unit,
    onDragEnd: (translation: Float, velocity: Float) -> Unit,
): Modifier = pointerInput(Unit) {
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false)
        val tracker = VelocityTracker()
        tracker.addPosition(down.uptimeMillis, down.position)
        var horizontal = 0f
        var vertical = 0f
        var active = false
        while (true) {
            val event = awaitPointerEvent()
            val change = event.changes.firstOrNull { it.id == down.id } ?: break
            tracker.addPosition(change.uptimeMillis, change.position)
            if (!change.pressed) break
            val delta = change.positionChange()
            horizontal += delta.x
            vertical += delta.y
            if (!active) {
                val slop = viewConfiguration.touchSlop
                if (abs(horizontal) > slop && abs(horizontal) > abs(vertical)) {
                    active = true
                    onDragStart()
                } else if (abs(vertical) > slop) {
                    break
                }
            }
            if (active) {
                change.consume()
                onDrag(horizontal)
            }
        }
        if (active) {
            onDragEnd(horizontal, tracker.calculateVelocity().x)
        }
    }
}

/** 从左缘起手的横向拖拽，用于拉出设置抽屉。 */
private fun Modifier.edgeDrawerGesture(
    enabled: Boolean,
    edgeWidthPx: Float,
    onDragStart: () -> Unit,
    onDrag: (translation: Float) -> Unit,
    onDragEnd: (translation: Float, velocity: Float) -> Unit,
): Modifier = pointerInput(enabled, edgeWidthPx) {
    if (!enabled) return@pointerInput
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false)
        if (down.position.x > edgeWidthPx) return@awaitEachGesture
        val tracker = VelocityTracker()
        tracker.addPosition(down.uptimeMillis, down.position)
        var horizontal = 0f
        var vertical = 0f
        var active = false
        while (true) {
            val event = awaitPointerEvent()
            val change = event.changes.firstOrNull { it.id == down.id } ?: break
            tracker.addPosition(change.uptimeMillis, change.position)
            if (!change.pressed) break
            val delta = change.positionChange()
            horizontal += delta.x
            vertical += delta.y
            if (!active) {
                val slop = viewConfiguration.touchSlop
                if (horizontal > slop && horizontal > abs(vertical)) {
                    active = true
                    onDragStart()
                } else if (horizontal < -slop || abs(vertical) > slop) {
                    break
                }
            }
            if (active) {
                change.consume()
                onDrag(horizontal.coerceAtLeast(0f))
            }
        }
        if (active) {
            onDragEnd(horizontal.coerceAtLeast(0f), tracker.calculateVelocity().x)
        }
    }
}

@Composable
private fun rememberReduceMotion(): Boolean {
    val context = LocalContext.current
    return remember(context) {
        val scale = Settings.Global.getFloat(
            context.contentResolver,
            Settings.Global.ANIMATOR_DURATION_SCALE,
            1f,
        )
        scale == 0f
    }
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}
