package cn.bobochang.sonar.ui.player

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Refresh
import androidx.compose.material.icons.rounded.Delete
import androidx.compose.material.icons.rounded.MoreHoriz
import androidx.compose.material.icons.rounded.MusicNote
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.Reorder
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import cn.bobochang.sonar.playback.PlayerUiState
import cn.bobochang.sonar.ui.components.PlayerArtwork
import cn.bobochang.sonar.ui.components.PlayingEqualizer
import kotlin.math.abs
import kotlin.math.roundToInt

private val PrimaryInk = Color.White.copy(alpha = 0.96f)
private val SecondaryInk = Color.White.copy(alpha = 0.62f)
private val TertiaryInk = Color.White.copy(alpha = 0.34f)
private const val ROW_HEIGHT = 68f

/** 对应 iOS `QueueFace(presentation: .player)`。 */
@Composable
fun QueueFace(
    state: PlayerUiState,
    onSelect: (Int) -> Unit,
    onRemove: (Int) -> Unit,
    onClearUpcoming: () -> Unit,
    onMove: (fromIndex: Int, insertionOffset: Int) -> Unit,
    onToggle: () -> Unit,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val currentIndex = state.index
    val upcoming = if (currentIndex >= 0) state.queue.drop(currentIndex + 1) else state.queue
    val current = if (currentIndex in state.queue.indices) state.queue[currentIndex] else null
    var dragPosition by remember { mutableIntStateOf(-1) }
    var dragTranslation by remember { mutableFloatStateOf(0f) }
    val listState = rememberLazyListState()

    Column(modifier.fillMaxSize().background(Color.Transparent)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(52.dp)
                .padding(horizontal = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(
                modifier = Modifier.weight(1f),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Icon(Icons.Rounded.MusicNote, contentDescription = null, tint = SecondaryInk, modifier = Modifier.size(14.dp))
                Text("待播放 ${state.queue.size} 首", color = SecondaryInk, fontSize = 12.sp)
            }
            Box(
                modifier = Modifier
                    .size(44.dp)
                    .clickable(enabled = currentIndex >= 0 && currentIndex < state.queue.lastIndex) { onClearUpcoming() },
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Rounded.Delete,
                    contentDescription = "清空待播",
                    tint = if (currentIndex >= 0 && currentIndex < state.queue.lastIndex) SecondaryInk else TertiaryInk,
                    modifier = Modifier.size(18.dp),
                )
            }
        }

        if (state.queue.isEmpty()) {
            Column(
                modifier = Modifier.fillMaxSize(),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.Center,
            ) {
                Icon(Icons.Rounded.MusicNote, contentDescription = null, tint = TertiaryInk, modifier = Modifier.size(34.dp))
                Spacer(Modifier.height(10.dp))
                Text("待播放为空", color = TertiaryInk, fontSize = 14.sp, fontWeight = FontWeight.Medium)
            }
            return@Column
        }

        LazyColumn(state = listState, modifier = Modifier.fillMaxSize()) {
            if (current != null) {
                item(key = "current-context") {
                    CurrentContext(
                        state = state,
                        title = current.title,
                        artist = current.artist,
                        artworkTrack = current,
                        onToggle = {
                            if (state.error != null) onRetry() else onToggle()
                        },
                        onRemove = { onRemove(currentIndex) },
                    )
                }
            }
            item(key = "upcoming-header") {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp)
                        .padding(top = 16.dp, bottom = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Text("接下来播放", color = PrimaryInk, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
                    Text("${upcoming.size} 首", color = SecondaryInk, fontSize = 12.sp)
                }
            }
            if (upcoming.isEmpty()) {
                item(key = "upcoming-empty") {
                    Text(
                        text = "接下来没有歌曲",
                        color = SecondaryInk,
                        fontSize = 15.sp,
                        modifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = 76.dp)
                            .padding(horizontal = 16.dp),
                    )
                }
            } else {
                itemsIndexed(upcoming, key = { _, track -> track.musicId }) { position, track ->
                    val destination = if (dragPosition >= 0) {
                        val raw = dragPosition + (dragTranslation / ROW_HEIGHT).roundToInt()
                        raw.coerceIn(0, upcoming.lastIndex)
                    } else position
                    val offset = when {
                        dragPosition < 0 -> 0f
                        position == dragPosition -> dragTranslation
                        dragPosition < destination && position > dragPosition && position <= destination -> -ROW_HEIGHT
                        dragPosition > destination && position >= destination && position < dragPosition -> ROW_HEIGHT
                        else -> 0f
                    }
                    QueueRow(
                        title = track.title,
                        artist = track.artist,
                        artworkTrack = track,
                        dragging = dragPosition == position,
                        offset = offset.dp,
                        onClick = { onSelect(currentIndex + 1 + position) },
                        onRemove = { onRemove(currentIndex + 1 + position) },
                        onDragStart = {
                            dragPosition = position
                            dragTranslation = 0f
                        },
                        onDrag = { dragTranslation += it },
                        onDragEnd = {
                            val destinationPosition = (position + (dragTranslation / ROW_HEIGHT).roundToInt())
                                .coerceIn(0, upcoming.lastIndex)
                            val sourceQueueIndex = currentIndex + 1 + position
                            val destinationQueueIndex = currentIndex + 1 + destinationPosition
                            val insertion = if (sourceQueueIndex < destinationQueueIndex) {
                                destinationQueueIndex + 1
                            } else {
                                destinationQueueIndex
                            }
                            dragPosition = -1
                            dragTranslation = 0f
                            if (destinationPosition != position) {
                                onMove(sourceQueueIndex, insertion)
                            }
                        },
                    )
                }
            }
            item(key = "bottom-space") { Spacer(Modifier.height(24.dp)) }
        }
    }
}

@Composable
private fun CurrentContext(
    state: PlayerUiState,
    title: String,
    artist: String,
    artworkTrack: cn.bobochang.sonar.data.model.Track,
    onToggle: () -> Unit,
    onRemove: () -> Unit,
) {
    var menuOpen by remember { mutableStateOf(false) }
    Column {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(Color.White.copy(alpha = 0.045f))
                .padding(horizontal = 16.dp, vertical = 11.dp)
                .heightIn(min = 80.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            Modifier
                .size(58.dp)
                .background(Color.Black.copy(alpha = 0.30f), androidx.compose.foundation.shape.RoundedCornerShape(7.dp)),
            contentAlignment = Alignment.Center,
        ) {
            PlayerArtwork(track = artworkTrack, size = 58.dp, cornerRadius = 7.dp)
            Box(
                Modifier
                    .align(Alignment.BottomEnd)
                    .padding(4.dp)
                    .background(Color.Black.copy(alpha = 0.58f), androidx.compose.foundation.shape.RoundedCornerShape(4.dp))
                    .padding(2.dp),
            ) {
                PlayingEqualizer(isAnimating = state.isPlaying, color = Color.White)
            }
        }
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("当前播放", color = SecondaryInk, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
            Text(
                text = title,
                color = PrimaryInk,
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                text = artist,
                color = SecondaryInk,
                fontSize = 12.sp,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Box(Modifier.size(44.dp).clickable { onToggle() }, contentAlignment = Alignment.Center) {
            when {
                state.isLoading -> androidx.compose.material3.CircularProgressIndicator(
                    modifier = Modifier.size(22.dp),
                    color = PrimaryInk,
                    strokeWidth = 2.dp,
                )
                state.error != null -> Icon(Icons.Rounded.Refresh, contentDescription = "重试", tint = PrimaryInk, modifier = Modifier.size(30.dp))
                state.isPlaying -> Icon(Icons.Rounded.Pause, contentDescription = "暂停", tint = PrimaryInk, modifier = Modifier.size(30.dp))
                else -> Icon(Icons.Rounded.PlayArrow, contentDescription = "播放", tint = PrimaryInk, modifier = Modifier.size(32.dp))
            }
        }
        Box {
            Box(Modifier.size(44.dp).clickable { menuOpen = true }, contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.MoreHoriz, contentDescription = "管理当前歌曲", tint = SecondaryInk, modifier = Modifier.size(16.dp))
            }
            DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                DropdownMenuItem(
                    text = { Text("移出待播放") },
                    onClick = {
                        menuOpen = false
                        onRemove()
                    },
                )
            }
        }
    }
    HorizontalDivider(color = Color.White.copy(alpha = 0.08f), thickness = 0.5.dp)
    }
}

@Composable
private fun QueueRow(
    title: String,
    artist: String,
    artworkTrack: cn.bobochang.sonar.data.model.Track,
    dragging: Boolean,
    offset: androidx.compose.ui.unit.Dp,
    onClick: () -> Unit,
    onRemove: () -> Unit,
    onDragStart: () -> Unit,
    onDrag: (Float) -> Unit,
    onDragEnd: () -> Unit,
) {
    var menuOpen by remember { mutableStateOf(false) }
    Column {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(Color.White.copy(alpha = if (dragging) 0.10f else 0f))
            .padding(horizontal = 16.dp, vertical = 5.dp)
            .heightIn(min = 68.dp)
            .then(Modifier.offset(y = offset)),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Row(
            modifier = Modifier.weight(1f).clickable(onClick = onClick),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            PlayerArtwork(track = artworkTrack, size = 44.dp, cornerRadius = 6.dp)
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(
                    text = title,
                    color = PrimaryInk,
                    fontSize = 15.sp,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    text = artist,
                    color = SecondaryInk,
                    fontSize = 12.sp,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        Box(
            modifier = Modifier
                .size(44.dp)
                .pointerInput(Unit) {
                    detectDragGestures(
                        onDragStart = { onDragStart() },
                        onDragEnd = { onDragEnd() },
                        onDragCancel = { onDragEnd() },
                        onDrag = { change, amount ->
                            change.consume()
                            onDrag(amount.y)
                        },
                    )
                },
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Rounded.Reorder, contentDescription = "拖动排序", tint = TertiaryInk, modifier = Modifier.size(16.dp))
        }
        Box {
            Box(Modifier.size(44.dp).clickable { menuOpen = true }, contentAlignment = Alignment.Center) {
                Icon(Icons.Rounded.MoreHoriz, contentDescription = "管理", tint = TertiaryInk, modifier = Modifier.size(14.dp))
            }
            DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                DropdownMenuItem(
                    text = { Text("移出待播放") },
                    onClick = {
                        menuOpen = false
                        onRemove()
                    },
                )
            }
        }
    }
    HorizontalDivider(
        color = Color.White.copy(alpha = 0.10f),
        thickness = 0.5.dp,
        modifier = Modifier.padding(horizontal = 16.dp),
    )
    }
}
