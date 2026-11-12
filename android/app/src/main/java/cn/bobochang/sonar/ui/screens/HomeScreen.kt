package cn.bobochang.sonar.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Settings
import androidx.compose.material.icons.rounded.ArrowForward
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Search
import androidx.compose.material.icons.rounded.Shuffle
import androidx.compose.material.icons.rounded.GraphicEq
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.di.AppContainer
import cn.bobochang.sonar.playback.PlayerUiState
import cn.bobochang.sonar.ui.components.LocalToast
import cn.bobochang.sonar.ui.components.SongRow
import cn.bobochang.sonar.ui.components.SongTrailing
import cn.bobochang.sonar.ui.theme.bouncePress
import cn.bobochang.sonar.ui.theme.circleIconPress
import cn.bobochang.sonar.ui.components.normalizedImageUrl
import cn.bobochang.sonar.ui.components.PlayerArtwork
import cn.bobochang.sonar.ui.theme.LocalSonarPalette
import coil.compose.AsyncImage
import coil.request.ImageRequest
import kotlinx.coroutines.launch

/** 对应 iOS `DiscoverView(showsSpotlight: true)`。 */
@Composable
fun HomeScreen(
    container: AppContainer,
    playerState: PlayerUiState,
    bottomPadding: Dp,
    onOpenSearch: () -> Unit,
    onOpenSettings: () -> Unit,
    onShowCollection: () -> Unit,
    onSongAction: (Track) -> Unit,
) {
    val palette = LocalSonarPalette.current
    val toast = LocalToast.current
    val scope = rememberCoroutineScope()
    val favorites by container.library.observeFavorites()
        .collectAsState(initial = emptyList())
    val statusTop = WindowInsets.statusBars.asPaddingValues().calculateTopPadding()
    val featured = playerState.track ?: favorites.firstOrNull { it.source.isEnabled }
    val displayed = favorites.take(6)
    val caption = if (featured != null && favorites.any { it.musicId == featured.musicId }) {
        "来自你的收藏"
    } else {
        "正在聆听"
    }

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(palette.background),
    ) {
        item(key = "hero") {
            SpotlightHero(
                track = featured,
                caption = caption,
                statusTop = statusTop,
                onOpenSearch = onOpenSearch,
                onOpenSettings = onOpenSettings,
            )
        }
        item(key = "playlist-header") {
            PlaylistHeader(
                count = favorites.size,
                enabled = favorites.any { it.source.isEnabled },
                onPlayAll = {
                    if (favorites.isNotEmpty()) {
                        scope.launch {
                            val quality = container.settings.snapshot().quality
                            container.playerConnection.setPlaybackMode(cn.bobochang.sonar.playback.PlaybackMode.SEQUENCE)
                            container.playerConnection.playTracks(favorites, 0, quality)
                            toast.show("已开始播放 ${favorites.size} 首歌曲")
                        }
                    }
                },
                onShuffle = {
                    if (favorites.isNotEmpty()) {
                        scope.launch {
                            val quality = container.settings.snapshot().quality
                            container.playerConnection.setPlaybackMode(cn.bobochang.sonar.playback.PlaybackMode.SHUFFLE)
                            container.playerConnection.playTracks(favorites.shuffled(), 0, quality)
                            toast.show(
                                if (favorites.size == 1) "已开始播放" else "已随机播放 ${favorites.size} 首歌曲",
                            )
                        }
                    }
                },
            )
        }
        if (displayed.isNotEmpty()) {
            itemsIndexed(displayed, key = { _, track -> track.musicId }) { index, track ->
                SongRow(
                    track = track,
                    trailing = SongTrailing.More,
                    showAlbum = false,
                    showDivider = false,
                    isCurrent = playerState.track?.musicId == track.musicId,
                    isPlaying = playerState.isPlaying,
                    onPlay = {
                        scope.launch {
                            val quality = container.settings.snapshot().quality
                            container.playerConnection.setPlaybackMode(cn.bobochang.sonar.playback.PlaybackMode.SEQUENCE)
                            container.playerConnection.playTracks(favorites, index, quality)
                        }
                    },
                    onAction = { onSongAction(track) },
                )
            }
            if (favorites.size > displayed.size) {
                item(key = "all-favorites") {
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(52.dp)
                            .clickable(onClick = onShowCollection)
                            .padding(horizontal = 24.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = "查看全部 ${favorites.size} 首收藏",
                            color = palette.secondaryInk,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.Medium,
                        )
                        Spacer(Modifier.weight(1f))
                        Icon(Icons.Rounded.ArrowForward, contentDescription = null, tint = palette.secondaryInk, modifier = Modifier.size(13.dp))
                    }
                }
            }
        } else {
            item(key = "empty") {
                Column(
                    modifier = Modifier.fillMaxWidth().padding(vertical = 48.dp),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Text("从一首喜欢的歌开始", color = palette.ink, fontSize = 19.sp, fontWeight = FontWeight.SemiBold)
                    Text("搜索歌曲，将它们留在你的收藏里", color = palette.secondaryInk, fontSize = 13.sp)
                    Spacer(Modifier.height(8.dp))
                    PlayAllButton(
                        title = "搜索音乐",
                        icon = Icons.Rounded.Search,
                        foreground = palette.onAccent,
                        background = palette.accent,
                        onClick = onOpenSearch,
                        modifier = Modifier.padding(horizontal = 24.dp).width(200.dp),
                    )
                }
            }
        }
        item(key = "bottom-space") { Spacer(Modifier.height(bottomPadding + 20.dp)) }
    }
}

@Composable
private fun SpotlightHero(
    track: Track?,
    caption: String,
    statusTop: Dp,
    onOpenSearch: () -> Unit,
    onOpenSettings: () -> Unit,
) {
    val palette = LocalSonarPalette.current
    val context = LocalContext.current
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(380.dp + statusTop),
    ) {
        val url = track?.coverUrl
        if (!url.isNullOrBlank()) {
            AsyncImage(
                model = ImageRequest.Builder(context).data(normalizedImageUrl(url)).crossfade(true).build(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.matchParentSize(),
            )
        } else {
            Box(
                Modifier
                    .matchParentSize()
                    .background(
                        Brush.linearGradient(
                            listOf(palette.accentContainer, palette.background),
                        ),
                    ),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Rounded.GraphicEq,
                    contentDescription = null,
                    tint = palette.accent.copy(alpha = 0.28f),
                    modifier = Modifier.size(92.dp),
                )
            }
        }
        Box(
            Modifier
                .matchParentSize()
                .background(
                    Brush.verticalGradient(
                        0f to Color.Black.copy(alpha = 0.28f),
                        0.32f to Color.Black.copy(alpha = 0.04f),
                        0.72f to palette.background.copy(alpha = 0.60f),
                        1f to palette.background,
                    ),
                ),
        )
        Column(
            modifier = Modifier
                .align(Alignment.BottomStart)
                .padding(horizontal = 24.dp)
                .padding(bottom = 20.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Text(
                text = if (track == null) "你的音乐，从这里开始" else caption,
                color = palette.secondaryInk,
                fontSize = 10.sp,
                fontWeight = FontWeight.SemiBold,
                letterSpacing = 2.sp,
            )
            Text(
                text = track?.artist?.takeIf { it.isNotBlank() } ?: "听见你的音乐",
                color = palette.ink,
                fontSize = 39.sp,
                fontWeight = FontWeight.Bold,
                letterSpacing = (-1.4).sp,
                lineHeight = 44.sp,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = track?.album?.takeIf { it.isNotBlank() } ?: track?.title ?: "让每一首歌都有自己的位置",
                color = palette.secondaryInk,
                fontSize = 12.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        HomeHeader(
            modifier = Modifier.align(Alignment.TopStart),
            tint = Color.White,
            topPadding = statusTop + 4.dp,
            onOpenSearch = onOpenSearch,
            onOpenSettings = onOpenSettings,
        )
    }
}

@Composable
private fun HomeHeader(
    modifier: Modifier = Modifier,
    tint: Color,
    topPadding: Dp = 14.dp,
    onOpenSearch: () -> Unit,
    onOpenSettings: () -> Unit,
) {
    Row(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 22.dp)
            .padding(top = topPadding),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = "sonar",
            color = tint,
            fontSize = 23.sp,
            fontWeight = FontWeight.Bold,
            fontFamily = FontFamily.SansSerif,
        )
        Spacer(Modifier.weight(1f))
        HeaderIcon(Icons.Rounded.Search, "搜索", onOpenSearch)
        HeaderIcon(Icons.Rounded.Settings, "设置", onOpenSettings)
    }
}

@Composable
private fun HeaderIcon(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    description: String,
    onClick: () -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    Box(
        modifier = Modifier
            .size(44.dp)
            .then(circleIconPress(interaction, 38.dp))
            .clickableNoIndication(onClick, interaction),
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = description, tint = Color.White, modifier = Modifier.size(20.dp))
    }
}

@Composable
private fun PlaylistHeader(
    count: Int,
    enabled: Boolean,
    onPlayAll: () -> Unit,
    onShuffle: () -> Unit,
) {
    val palette = LocalSonarPalette.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp)
            .padding(bottom = 10.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("收藏歌曲", color = palette.ink, fontSize = 20.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.weight(1f))
            Text("$count 首歌曲", color = palette.secondaryInk, fontSize = 11.sp)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            PlayAllButton(
                title = "播放全部",
                icon = Icons.Rounded.PlayArrow,
                foreground = palette.onAccent,
                background = palette.accent,
                enabled = enabled,
                onClick = onPlayAll,
                modifier = Modifier.weight(1f),
            )
            PlayAllButton(
                title = "随机播放",
                icon = Icons.Rounded.Shuffle,
                foreground = palette.ink,
                background = palette.elevated,
                enabled = enabled,
                onClick = onShuffle,
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun PlayAllButton(
    title: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    foreground: Color,
    background: Color,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    val interaction = remember { MutableInteractionSource() }
    Box(
        modifier = modifier
            .height(44.dp)
            .then(bouncePress(interaction, 0.96f, 0.9f, haptic = false))
            .clickableNoIndication(onClick, interaction, enabled),
        contentAlignment = Alignment.Center,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(40.dp)
                .background(background, RoundedCornerShape(8.dp))
                .padding(horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.Center,
        ) {
            Icon(icon, contentDescription = null, tint = foreground.copy(alpha = if (enabled) 1f else 0.45f), modifier = Modifier.size(14.dp))
            Spacer(Modifier.size(6.dp))
            Text(
                text = title,
                color = foreground.copy(alpha = if (enabled) 1f else 0.45f),
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
            )
        }
    }
}

internal fun Modifier.clickableNoIndication(
    onClick: () -> Unit,
    interactionSource: MutableInteractionSource? = null,
    enabled: Boolean = true,
): Modifier = this.clickable(
    interactionSource = interactionSource,
    indication = null,
    enabled = enabled,
    onClick = onClick,
)
