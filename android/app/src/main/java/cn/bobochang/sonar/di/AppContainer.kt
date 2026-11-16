package cn.bobochang.sonar.di

import android.content.Context
import cn.bobochang.sonar.data.cache.AudioCacheStore
import cn.bobochang.sonar.data.library.LibraryDatabase
import cn.bobochang.sonar.data.library.LibraryRepository
import cn.bobochang.sonar.data.local.LocalMusicImporter
import cn.bobochang.sonar.data.net.ChkszClient
import cn.bobochang.sonar.data.net.ConnectivityMonitor
import cn.bobochang.sonar.data.net.NetEaseWebClient
import cn.bobochang.sonar.data.playback.PlaybackRepository
import cn.bobochang.sonar.data.prefs.CredentialStore
import cn.bobochang.sonar.data.prefs.SettingsRepository
import cn.bobochang.sonar.lyrics.LyricsRepository
import cn.bobochang.sonar.playback.PlayerConnection
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

class AppContainer(context: Context) {
    private val appContext = context.applicationContext

    val appScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    val credentials = CredentialStore(appContext)
    val settings = SettingsRepository(appContext)
    val connectivity = ConnectivityMonitor(appContext)

    private val database = LibraryDatabase.create(appContext)
    val library = LibraryRepository(database)
    val audioCache = AudioCacheStore(appContext, database.dao())
    val localImporter = LocalMusicImporter(appContext)

    val netEase = NetEaseWebClient(cookieProvider = { credentials.neteaseCookie() })
    val chksz = ChkszClient(keyProvider = { credentials.chkszKey() })
    val playback = PlaybackRepository(
        netEase = netEase,
        chksz = chksz,
        cache = audioCache,
        settings = settings,
        connectivity = connectivity,
    )
    val lyrics = LyricsRepository(appContext, netEase, chksz)

    val playerConnection: PlayerConnection by lazy { PlayerConnection(appContext, playback) }
}
