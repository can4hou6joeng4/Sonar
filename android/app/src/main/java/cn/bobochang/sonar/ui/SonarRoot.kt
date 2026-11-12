package cn.bobochang.sonar.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.FavoriteBorder
import androidx.compose.material.icons.rounded.LibraryMusic
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import cn.bobochang.sonar.data.prefs.SonarSettings
import cn.bobochang.sonar.di.AppContainer
import cn.bobochang.sonar.ui.components.AddToPlaylistHost
import cn.bobochang.sonar.ui.components.MiniPlayer
import cn.bobochang.sonar.ui.screens.AlbumDetailScreen
import cn.bobochang.sonar.ui.screens.ArtistDetailScreen
import cn.bobochang.sonar.ui.screens.HomeScreen
import cn.bobochang.sonar.ui.screens.LibraryScreen
import cn.bobochang.sonar.ui.screens.PlaylistDetailScreen
import cn.bobochang.sonar.ui.screens.PlayerScreen
import cn.bobochang.sonar.ui.screens.RemotePlaylistScreen
import cn.bobochang.sonar.ui.screens.SearchScreen
import cn.bobochang.sonar.ui.screens.SettingsScreen
import cn.bobochang.sonar.ui.theme.LocalSonarPalette
import cn.bobochang.sonar.ui.theme.SonarTheme

private data class RootTab(
    val route: String,
    val label: String,
    val icon: ImageVector,
)

private val rootTabs = listOf(
    RootTab("home", "音乐", Icons.Rounded.LibraryMusic),
    RootTab("search", "搜索", Icons.Rounded.Search),
    RootTab("library", "资料库", Icons.Rounded.FavoriteBorder),
    RootTab("settings", "设置", Icons.Rounded.Settings),
)

private val rootRoutes = rootTabs.map { it.route }.toSet()

@Composable
fun SonarRoot(container: AppContainer) {
    val settings by container.settings.settings.collectAsStateWithLifecycle(initialValue = SonarSettings())
    SonarTheme(themeMode = settings.themeMode) {
        val palette = LocalSonarPalette.current
        val navController = rememberNavController()
        val backStack by navController.currentBackStackEntryAsState()
        val route = backStack?.destination?.route
        val playerState by container.playerConnection.state.collectAsStateWithLifecycle()
        val snackbarHostState = remember { SnackbarHostState() }
        val showChrome = route in rootRoutes || route == null

        Scaffold(
            containerColor = palette.background,
            snackbarHost = { SnackbarHost(snackbarHostState) },
            bottomBar = {
                if (showChrome) {
                    Column {
                        MiniPlayer(
                            state = playerState,
                            onOpen = { navController.navigate("player") },
                            onToggle = { container.playerConnection.toggle() },
                            onNext = { container.playerConnection.next() },
                        )
                        NavigationBar(
                            containerColor = palette.background,
                            tonalElevation = 0.dp,
                        ) {
                            rootTabs.forEach { tab ->
                                val selected = route == tab.route
                                NavigationBarItem(
                                    selected = selected,
                                    onClick = {
                                        navController.navigate(tab.route) {
                                            popUpTo(navController.graph.findStartDestination().id) {
                                                saveState = true
                                            }
                                            launchSingleTop = true
                                            restoreState = true
                                        }
                                    },
                                    icon = {
                                        Icon(
                                            imageVector = tab.icon,
                                            contentDescription = tab.label,
                                        )
                                    },
                                    label = { androidx.compose.material3.Text(tab.label) },
                                    colors = NavigationBarItemDefaults.colors(
                                        selectedIconColor = palette.accent,
                                        selectedTextColor = palette.accent,
                                        indicatorColor = palette.accent.copy(alpha = 0.14f),
                                        unselectedIconColor = palette.secondaryInk,
                                        unselectedTextColor = palette.secondaryInk,
                                    ),
                                )
                            }
                        }
                    }
                }
            },
        ) { padding ->
            AddToPlaylistHost(container = container, snackbarHostState = snackbarHostState) {
            NavHost(
                navController = navController,
                startDestination = "home",
                modifier = Modifier.padding(padding),
            ) {
                composable("home") {
                    HomeScreen(
                        container = container,
                        snackbarHostState = snackbarHostState,
                        onOpenSearch = { navController.navigate("search") },
                        onOpenLibrary = { navController.navigate("library") },
                        onOpenSettings = { navController.navigate("settings") },
                        onOpenPlayer = { navController.navigate("player") },
                        onOpenFavorites = { navController.navigate("favorites") },
                        onOpenPlaylist = { id -> navController.navigate("playlist/$id") },
                    )
                }
                composable("search") {
                    SearchScreen(
                        container = container,
                        snackbarHostState = snackbarHostState,
                        onOpenPlayer = { navController.navigate("player") },
                        onOpenArtist = { id -> navController.navigate("artist/$id") },
                        onOpenAlbum = { id -> navController.navigate("album/$id") },
                        onOpenPlaylist = { id -> navController.navigate("remote/$id") },
                    )
                }
                composable("library") {
                    LibraryScreen(
                        container = container,
                        snackbarHostState = snackbarHostState,
                        onOpenPlayer = { navController.navigate("player") },
                        onOpenFavorites = { navController.navigate("favorites") },
                        onOpenPlaylist = { id -> navController.navigate("playlist/$id") },
                        onOpenLocal = { navController.navigate("favorites") },
                    )
                }
                composable("settings") {
                    SettingsScreen(container = container, snackbarHostState = snackbarHostState)
                }
                composable("player") {
                    PlayerScreen(
                        container = container,
                        onBack = { navController.popBackStack() },
                        onOpenQueue = { },
                    )
                }
                composable("favorites") {
                    PlaylistDetailScreen(
                        container = container,
                        playlistId = null,
                        onBack = { navController.popBackStack() },
                        onOpenPlayer = { navController.navigate("player") },
                        snackbarHostState = snackbarHostState,
                    )
                }
                composable("playlist/{id}") { entry ->
                    PlaylistDetailScreen(
                        container = container,
                        playlistId = entry.arguments?.getString("id"),
                        onBack = { navController.popBackStack() },
                        onOpenPlayer = { navController.navigate("player") },
                        snackbarHostState = snackbarHostState,
                    )
                }
                composable("remote/{id}") { entry ->
                    RemotePlaylistScreen(
                        container = container,
                        playlistId = entry.arguments?.getString("id").orEmpty(),
                        onBack = { navController.popBackStack() },
                        onOpenPlayer = { navController.navigate("player") },
                        snackbarHostState = snackbarHostState,
                    )
                }
                composable("artist/{id}") { entry ->
                    ArtistDetailScreen(
                        container = container,
                        artistId = entry.arguments?.getString("id").orEmpty(),
                        onBack = { navController.popBackStack() },
                        onOpenPlayer = { navController.navigate("player") },
                        onOpenAlbum = { id -> navController.navigate("album/$id") },
                        snackbarHostState = snackbarHostState,
                    )
                }
                composable("album/{id}") { entry ->
                    AlbumDetailScreen(
                        container = container,
                        albumId = entry.arguments?.getString("id").orEmpty(),
                        onBack = { navController.popBackStack() },
                        onOpenPlayer = { navController.navigate("player") },
                        snackbarHostState = snackbarHostState,
                    )
                }
            }
            }
        }
    }
}
