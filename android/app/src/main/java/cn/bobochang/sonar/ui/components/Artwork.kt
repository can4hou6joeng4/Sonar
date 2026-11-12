package cn.bobochang.sonar.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.ui.theme.LocalSonarPalette
import coil.compose.AsyncImage
import coil.request.ImageRequest

/** 统一的曲目封面，对应 iOS `PlayerArtwork`。 */
@Composable
fun PlayerArtwork(
    track: Track?,
    size: Dp,
    modifier: Modifier = Modifier,
    circular: Boolean = false,
    cornerRadius: Dp = 10.dp,
    animatesChanges: Boolean = false,
) {
    val palette = LocalSonarPalette.current
    val shape = if (circular) CircleShape else RoundedCornerShape(cornerRadius)
    Box(
        modifier = modifier
            .size(size)
            .clip(shape)
            .background(palette.elevated),
        contentAlignment = Alignment.Center,
    ) {
        val url = track?.coverUrl
        if (!url.isNullOrBlank()) {
            AsyncImage(
                model = ImageRequest.Builder(LocalContext.current)
                    .data(normalizedImageUrl(url))
                    .crossfade(animatesChanges)
                    .build(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            Icon(
                imageVector = Icons.Rounded.MusicNote,
                contentDescription = null,
                tint = palette.ink.copy(alpha = 0.72f),
                modifier = Modifier.size(if (size > 100.dp) 52.dp else 19.dp),
            )
        }
    }
}

/** 旧调用点兼容：只传 URL。 */
@Composable
fun Artwork(
    url: String?,
    size: Dp,
    modifier: Modifier = Modifier,
    corner: Dp = 10.dp,
    tint: Color? = null,
) {
    val palette = LocalSonarPalette.current
    Box(
        modifier = modifier
            .size(size)
            .clip(RoundedCornerShape(corner))
            .background(tint ?: palette.elevated),
        contentAlignment = Alignment.Center,
    ) {
        if (!url.isNullOrBlank()) {
            AsyncImage(
                model = ImageRequest.Builder(LocalContext.current)
                    .data(normalizedImageUrl(url))
                    .crossfade(true)
                    .build(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            Icon(
                imageVector = Icons.Rounded.MusicNote,
                contentDescription = null,
                tint = palette.secondaryInk,
                modifier = Modifier.size(size * 0.42f),
            )
        }
    }
}

/** 远程歌单 / 歌手 / 专辑封面（对应 iOS `RemotePlaylistArtwork`）。 */
@Composable
fun RemoteArtwork(
    url: String?,
    size: Dp,
    modifier: Modifier = Modifier,
    cornerRadius: Dp = 8.dp,
    circular: Boolean = false,
) {
    val palette = LocalSonarPalette.current
    val shape = if (circular) CircleShape else RoundedCornerShape(cornerRadius)
    Box(
        modifier = modifier
            .size(size)
            .clip(shape)
            .background(palette.elevated),
        contentAlignment = Alignment.Center,
    ) {
        if (!url.isNullOrBlank()) {
            AsyncImage(
                model = ImageRequest.Builder(LocalContext.current)
                    .data(normalizedImageUrl(url))
                    .crossfade(true)
                    .build(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        } else {
            Icon(
                imageVector = Icons.Rounded.MusicNote,
                contentDescription = null,
                tint = palette.secondaryInk,
                modifier = Modifier.size(size * 0.38f),
            )
        }
    }
}

internal fun normalizedImageUrl(url: String): String = when {
    url.startsWith("//") -> "https:$url"
    url.startsWith("http://") -> "https://" + url.removePrefix("http://")
    else -> url
}
