package cn.bobochang.sonar.data.library

import android.content.Context
import androidx.room.Dao
import androidx.room.Database
import androidx.room.Entity
import androidx.room.Index
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.PrimaryKey
import androidx.room.Query
import androidx.room.Room
import androidx.room.RoomDatabase
import cn.bobochang.sonar.data.model.MusicSource
import cn.bobochang.sonar.data.model.SonarJson
import cn.bobochang.sonar.data.model.Track
import cn.bobochang.sonar.data.model.wire
import kotlinx.coroutines.flow.Flow
import kotlinx.serialization.json.jsonObject

@Entity(tableName = "tracks")
data class TrackEntity(
    @PrimaryKey val musicId: String,
    val source: String,
    val songmid: String,
    val title: String,
    val artist: String,
    val album: String,
    val interval: String?,
    val payload: String,
    val updatedAt: Long,
) {
    fun toTrack(): Track? = runCatching {
        Track(
            source = MusicSource.fromWire(source),
            songmid = songmid,
            title = title,
            artist = artist,
            album = album,
            interval = interval,
            payload = SonarJson.parseToJsonElement(payload).jsonObject,
        )
    }.getOrNull()

    companion object {
        fun from(track: Track, now: Long = System.currentTimeMillis()): TrackEntity = TrackEntity(
            musicId = track.musicId,
            source = track.source.wire,
            songmid = track.songmid,
            title = track.title,
            artist = track.artist,
            album = track.album,
            interval = track.interval,
            payload = track.payload.toString(),
            updatedAt = now,
        )
    }
}

@Entity(tableName = "favorites")
data class FavoriteEntity(
    @PrimaryKey val musicId: String,
    val addedAt: Long,
)

@Entity(tableName = "playlists")
data class PlaylistEntity(
    @PrimaryKey val id: String,
    val name: String,
    val createdAt: Long,
    val updatedAt: Long,
    val system: Boolean = false,
)

@Entity(
    tableName = "playlist_tracks",
    primaryKeys = ["playlistId", "musicId"],
    indices = [Index("playlistId"), Index("musicId")],
)
data class PlaylistTrackEntity(
    val playlistId: String,
    val musicId: String,
    val position: Int,
    val addedAt: Long,
)

@Entity(tableName = "recent_plays")
data class RecentPlayEntity(
    @PrimaryKey val musicId: String,
    val playedAt: Long,
)

@Entity(tableName = "cached_audio")
data class CachedAudioEntity(
    @PrimaryKey val cacheKey: String,
    val musicId: String,
    val quality: String,
    val fileName: String,
    val size: Long,
    val savedAt: Long,
)

@Entity(tableName = "search_history")
data class SearchHistoryEntity(
    @PrimaryKey val query: String,
    val searchedAt: Long,
)

@Dao
interface LibraryDao {
    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertTracks(tracks: List<TrackEntity>)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsertTrack(track: TrackEntity)

    @Query("SELECT * FROM tracks WHERE musicId = :musicId LIMIT 1")
    suspend fun track(musicId: String): TrackEntity?

    @Query("SELECT * FROM tracks WHERE musicId IN (:musicIds)")
    suspend fun tracks(musicIds: List<String>): List<TrackEntity>

    @Query(
        "SELECT t.* FROM tracks t INNER JOIN favorites f ON f.musicId = t.musicId " +
            "ORDER BY f.addedAt DESC",
    )
    fun observeFavorites(): Flow<List<TrackEntity>>

    @Query("SELECT musicId FROM favorites ORDER BY addedAt DESC")
    suspend fun favoriteIds(): List<String>

    @Query(
        "SELECT t.* FROM tracks t INNER JOIN favorites f ON f.musicId = t.musicId " +
            "ORDER BY f.addedAt DESC",
    )
    suspend fun favoritesOnce(): List<TrackEntity>

    @Query("SELECT COUNT(*) FROM favorites")
    fun observeFavoriteCount(): Flow<Int>

    @Query("SELECT EXISTS(SELECT 1 FROM favorites WHERE musicId = :musicId)")
    fun observeIsFavorite(musicId: String): Flow<Boolean>

    @Query("SELECT EXISTS(SELECT 1 FROM favorites WHERE musicId = :musicId)")
    suspend fun isFavorite(musicId: String): Boolean

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun addFavorite(favorite: FavoriteEntity)

    @Query("DELETE FROM favorites WHERE musicId = :musicId")
    suspend fun removeFavorite(musicId: String)

    @Query("SELECT * FROM playlists ORDER BY createdAt ASC")
    fun observePlaylists(): Flow<List<PlaylistEntity>>

    @Query("SELECT * FROM playlists WHERE id = :id LIMIT 1")
    suspend fun playlist(id: String): PlaylistEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertPlaylist(playlist: PlaylistEntity)

    @Query("UPDATE playlists SET name = :name, updatedAt = :now WHERE id = :id")
    suspend fun renamePlaylist(id: String, name: String, now: Long)

    @Query("DELETE FROM playlists WHERE id = :id")
    suspend fun deletePlaylist(id: String)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertPlaylistTracks(items: List<PlaylistTrackEntity>)

    @Query("DELETE FROM playlist_tracks WHERE playlistId = :playlistId")
    suspend fun clearPlaylistTracks(playlistId: String)

    @Query(
        "SELECT t.* FROM tracks t INNER JOIN playlist_tracks pt ON pt.musicId = t.musicId " +
            "WHERE pt.playlistId = :playlistId ORDER BY pt.position ASC",
    )
    fun observePlaylistTracks(playlistId: String): Flow<List<TrackEntity>>

    @Query("SELECT * FROM playlist_tracks WHERE playlistId = :playlistId ORDER BY position ASC")
    suspend fun playlistItems(playlistId: String): List<PlaylistTrackEntity>

    @Query(
        "SELECT t.* FROM tracks t INNER JOIN playlist_tracks pt ON pt.musicId = t.musicId " +
            "WHERE pt.playlistId = :playlistId ORDER BY pt.position ASC",
    )
    suspend fun playlistTracksOnce(playlistId: String): List<TrackEntity>

    @Query("SELECT MAX(position) FROM playlist_tracks WHERE playlistId = :playlistId")
    suspend fun maxPosition(playlistId: String): Int?

    @Query("DELETE FROM playlist_tracks WHERE playlistId = :playlistId AND musicId = :musicId")
    suspend fun removeFromPlaylist(playlistId: String, musicId: String)

    @Query("UPDATE playlist_tracks SET position = :position WHERE playlistId = :playlistId AND musicId = :musicId")
    suspend fun updatePlaylistPosition(playlistId: String, musicId: String, position: Int)

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun touchRecent(recent: RecentPlayEntity)

    @Query(
        "SELECT t.* FROM tracks t INNER JOIN recent_plays r ON r.musicId = t.musicId " +
            "ORDER BY r.playedAt DESC LIMIT :limit",
    )
    fun observeRecent(limit: Int): Flow<List<TrackEntity>>

    @Query(
        "DELETE FROM recent_plays WHERE musicId NOT IN " +
            "(SELECT musicId FROM recent_plays ORDER BY playedAt DESC LIMIT 100)",
    )
    suspend fun trimRecent()

    @Query("SELECT * FROM search_history ORDER BY searchedAt DESC LIMIT 10")
    fun observeSearchHistory(): Flow<List<SearchHistoryEntity>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun addSearchHistory(entry: SearchHistoryEntity)

    @Query("DELETE FROM search_history WHERE query = :query")
    suspend fun removeSearchHistory(query: String)

    @Query("DELETE FROM search_history")
    suspend fun clearSearchHistory()

    @Query("SELECT * FROM tracks WHERE source = 'local' ORDER BY updatedAt DESC")
    fun observeLocalTracks(): Flow<List<TrackEntity>>

    @Query("SELECT * FROM cached_audio WHERE musicId = :musicId")
    suspend fun cachedFor(musicId: String): List<CachedAudioEntity>

    @Query("SELECT * FROM cached_audio")
    suspend fun allCached(): List<CachedAudioEntity>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertCached(entry: CachedAudioEntity)

    @Query("DELETE FROM cached_audio WHERE cacheKey = :cacheKey")
    suspend fun deleteCached(cacheKey: String)

    @Query("DELETE FROM cached_audio")
    suspend fun clearCached()

    @Query("SELECT COUNT(*) FROM cached_audio")
    fun observeCacheCount(): Flow<Int>

    @Query("SELECT COALESCE(SUM(size), 0) FROM cached_audio")
    fun observeCacheBytes(): Flow<Long>
}

@Database(
    entities = [
        TrackEntity::class,
        FavoriteEntity::class,
        PlaylistEntity::class,
        PlaylistTrackEntity::class,
        RecentPlayEntity::class,
        CachedAudioEntity::class,
        SearchHistoryEntity::class,
    ],
    version = 1,
    exportSchema = true,
)
abstract class LibraryDatabase : RoomDatabase() {
    abstract fun dao(): LibraryDao

    companion object {
        fun create(context: Context): LibraryDatabase =
            Room.databaseBuilder(context.applicationContext, LibraryDatabase::class.java, "sonar-library.db")
                .build()
    }
}
