package cn.bobochang.sonar.data.library

import androidx.room.withTransaction
import cn.bobochang.sonar.data.model.Track
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import java.util.UUID

data class UserPlaylist(
    val id: String,
    val name: String,
    val system: Boolean,
    val createdAt: Long,
)

data class ImportResult(
    val playlistName: String,
    val inserted: Int,
    val skipped: Int,
    val total: Int,
)

sealed interface BackupTarget {
    data object Favorites : BackupTarget
    data class Playlist(val id: String) : BackupTarget
    data object NewPlaylist : BackupTarget
}

class LibraryRepository(private val database: LibraryDatabase) {
    private val dao = database.dao()

    fun observeFavorites(): Flow<List<Track>> =
        dao.observeFavorites().map { rows -> rows.mapNotNull(TrackEntity::toTrack) }

    fun observeFavoriteEntries(): Flow<List<PlaylistEntry>> =
        dao.observeFavoriteEntries().map { rows -> rows.mapNotNull(PlaylistTrackRow::toEntry) }

    fun observePlaylistEntries(playlistId: String): Flow<List<PlaylistEntry>> =
        dao.observePlaylistEntries(playlistId).map { rows -> rows.mapNotNull(PlaylistTrackRow::toEntry) }

    fun observeFavoriteCount(): Flow<Int> = dao.observeFavoriteCount()

    fun observeFavoriteIds(): Flow<Set<String>> =
        dao.observeFavorites().map { rows -> rows.map { it.musicId }.toSet() }

    fun observeIsFavorite(musicId: String): Flow<Boolean> = dao.observeIsFavorite(musicId)

    fun observeRecent(): Flow<List<Track>> =
        dao.observeRecent(100).map { rows -> rows.mapNotNull(TrackEntity::toTrack) }

    fun observeLocalTracks(): Flow<List<Track>> =
        dao.observeLocalTracks().map { rows -> rows.mapNotNull(TrackEntity::toTrack) }

    fun observePlaylists(): Flow<List<UserPlaylist>> =
        dao.observePlaylists().map { rows ->
            rows.map { UserPlaylist(it.id, it.name, it.system, it.createdAt) }
        }

    fun observePlaylistTracks(playlistId: String): Flow<List<Track>> =
        dao.observePlaylistTracks(playlistId).map { rows -> rows.mapNotNull(TrackEntity::toTrack) }

    fun observeSearchHistory(): Flow<List<String>> =
        dao.observeSearchHistory().map { rows -> rows.map { it.query } }

    suspend fun playlist(id: String): PlaylistEntity? = dao.playlist(id)

    suspend fun isFavorite(musicId: String): Boolean = dao.isFavorite(musicId)

    suspend fun toggleFavorite(track: Track): Boolean = database.withTransaction {
        val now = System.currentTimeMillis()
        if (dao.isFavorite(track.musicId)) {
            dao.removeFavorite(track.musicId)
            false
        } else {
            dao.upsertTrack(TrackEntity.from(track, now))
            dao.addFavorite(FavoriteEntity(track.musicId, now))
            true
        }
    }

    /** 明确添加，不切换状态；重复添加保留原成员时间。 */
    suspend fun addFavorite(track: Track): Boolean = database.withTransaction {
        if (dao.isFavorite(track.musicId)) return@withTransaction false
        val now = System.currentTimeMillis()
        dao.upsertTrack(TrackEntity.from(track, now))
        dao.addFavorite(FavoriteEntity(track.musicId, now))
        true
    }

    suspend fun removeFavorites(musicIds: Collection<String>) {
        database.withTransaction { musicIds.distinct().forEach { dao.removeFavorite(it) } }
    }

    suspend fun recordPlay(track: Track) {
        val now = System.currentTimeMillis()
        database.withTransaction {
            dao.upsertTrack(TrackEntity.from(track, now))
            dao.touchRecent(RecentPlayEntity(track.musicId, now))
            dao.trimRecent()
        }
    }

    suspend fun createPlaylist(name: String): String {
        val trimmed = name.trim().take(200).ifEmpty { "新建歌单" }
        val id = UUID.randomUUID().toString()
        val now = System.currentTimeMillis()
        dao.insertPlaylist(PlaylistEntity(id = id, name = trimmed, createdAt = now, updatedAt = now))
        return id
    }

    suspend fun renamePlaylist(id: String, name: String) {
        val trimmed = name.trim().take(200)
        if (trimmed.isNotEmpty()) dao.renamePlaylist(id, trimmed, System.currentTimeMillis())
    }

    suspend fun deletePlaylist(id: String) {
        database.withTransaction {
            dao.clearPlaylistTracks(id)
            dao.deletePlaylist(id)
        }
    }

    suspend fun addTracksToPlaylist(playlistId: String, tracks: List<Track>): Int {
        if (tracks.isEmpty()) return 0
        return database.withTransaction {
            requireNotNull(dao.playlist(playlistId)) { "歌单不存在或已删除，请重新选择" }
            val existing = dao.playlistItems(playlistId).mapTo(mutableSetOf()) { it.musicId }
            var position = (dao.maxPosition(playlistId) ?: -1) + 1
            val now = System.currentTimeMillis()
            val newRows = mutableListOf<PlaylistTrackEntity>()
            val newTracks = mutableListOf<TrackEntity>()
            for (track in tracks) {
                if (!existing.add(track.musicId)) continue
                newTracks += TrackEntity.from(track, now)
                newRows += PlaylistTrackEntity(playlistId, track.musicId, position++, now)
            }
            if (newTracks.isNotEmpty()) {
                dao.upsertTracks(newTracks)
                dao.insertPlaylistTracks(newRows)
            }
            newRows.size
        }
    }

    suspend fun removeFromPlaylist(playlistId: String, musicId: String) {
        dao.removeFromPlaylist(playlistId, musicId)
    }

    /** 批量移除同一事务完成，失败时不留下只删了一半的歌单。 */
    suspend fun removeFromPlaylist(playlistId: String, musicIds: Collection<String>) {
        database.withTransaction { musicIds.distinct().forEach { dao.removeFromPlaylist(playlistId, it) } }
    }

    suspend fun moveInPlaylist(playlistId: String, from: Int, to: Int) {
        if (from == to) return
        database.withTransaction {
            val items = dao.playlistItems(playlistId).toMutableList()
            if (from !in items.indices || to !in items.indices) return@withTransaction
            val moved = items.removeAt(from)
            items.add(to, moved)
            dao.insertPlaylistTracks(
                items.mapIndexed { index, item ->
                    item.copy(position = index)
                },
            )
        }
    }

    suspend fun importTracks(target: BackupTarget, name: String, tracks: List<Track>): ImportResult {
        val distinct = tracks.distinctBy { it.musicId }
        return when (target) {
            BackupTarget.Favorites -> {
                val existing = dao.favoriteIds().toMutableSet()
                val now = System.currentTimeMillis()
                var inserted = 0
                database.withTransaction {
                    for (track in distinct) {
                        if (!existing.add(track.musicId)) continue
                        dao.upsertTrack(TrackEntity.from(track, now))
                        dao.addFavorite(FavoriteEntity(track.musicId, now))
                        inserted++
                    }
                }
                ImportResult(name, inserted, tracks.size - inserted, tracks.size)
            }

            is BackupTarget.Playlist -> {
                val inserted = addTracksToPlaylist(target.id, distinct)
                ImportResult(name, inserted, tracks.size - inserted, tracks.size)
            }

            BackupTarget.NewPlaylist -> {
                val id = createPlaylist(name)
                val inserted = addTracksToPlaylist(id, distinct)
                ImportResult(name, inserted, tracks.size - inserted, tracks.size)
            }
        }
    }

    suspend fun exportFavorites(): String {
        val rows = dao.favoritesOnce()
        return PlaylistBackupCodec.encode("我的收藏", rows.mapNotNull(TrackEntity::toTrack))
    }

    suspend fun exportPlaylist(id: String): String? {
        val playlist = dao.playlist(id) ?: return null
        val rows = dao.playlistTracksOnce(id)
        return PlaylistBackupCodec.encode(playlist.name, rows.mapNotNull(TrackEntity::toTrack))
    }

    suspend fun importBackup(bytes: ByteArray, target: BackupTarget): ImportResult {
        val imported = PlaylistBackupCodec.decode(bytes)
        return importTracks(target, imported.name, imported.tracks)
    }

    suspend fun addSearchHistory(query: String) {
        val trimmed = query.trim().take(200)
        if (trimmed.isEmpty()) return
        dao.addSearchHistory(SearchHistoryEntity(trimmed, System.currentTimeMillis()))
    }

    suspend fun clearSearchHistory() = dao.clearSearchHistory()

    suspend fun removeSearchHistory(query: String) = dao.removeSearchHistory(query)
}
