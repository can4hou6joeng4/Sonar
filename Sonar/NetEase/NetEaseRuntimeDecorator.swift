import Foundation

/// 在既有 ChKSz 运行时之上补齐「歌手 / 专辑 / 搜索分类 / 歌词增强 / 播放直连」。
///
/// 只接管需要的内容接口，其余（搜索、歌单导入、热门搜索）继续走原运行时，
/// 保证下线的功能不会被无意启用。
public final class NetEaseRuntimeDecorator: SourceRuntime, @unchecked Sendable {
    private let base: SourceRuntime
    private let client: NetEaseWebClient

    public init(base: SourceRuntime, client: NetEaseWebClient) {
        self.base = base
        self.client = client
    }

    // MARK: - 原样转发

    public func search(_ keyword: String, source: MusicSource, page: Int) async throws -> SearchPage {
        try await base.search(keyword, source: source, page: page)
    }

    public func tipSearch(_ keyword: String) async throws -> [String] {
        let values = (try? await client.searchSuggestions(keyword)) ?? []
        if !values.isEmpty { return values }
        return try await base.tipSearch(keyword)
    }

    public func hotSearch(source: MusicSource) async throws -> [String] {
        guard source == .wy else { return try await base.hotSearch(source: source) }
        let values = (try? await client.hotSearches()) ?? []
        if !values.isEmpty { return values }
        return try await base.hotSearch(source: source)
    }

    public func playlistSearch(_ keyword: String, source: MusicSource, page: Int) async throws -> PlaylistCatalogPage {
        guard source == .wy else {
            return try await base.playlistSearch(keyword, source: source, page: page)
        }
        let limit = 20
        let offset = max(0, (max(1, page) - 1) * limit)
        let result = try await client.searchPlaylists(keyword, limit: limit, offset: offset)
        return PlaylistCatalogPage(
            list: result.playlists,
            total: result.total,
            page: page,
            limit: limit,
            source: .wy
        )
    }

    public func playlistCatalog(source: MusicSource, sortId: String, tagId: String?, page: Int) async throws -> PlaylistCatalogPage {
        try await base.playlistCatalog(source: source, sortId: sortId, tagId: tagId, page: page)
    }

    public func playlistDetail(source: MusicSource, id: String, page: Int) async throws -> PlaylistDetail {
        guard source == .wy else {
            return try await base.playlistDetail(source: source, id: id, page: page)
        }
        return try await client.playlistDetail(id: id)
    }

    // MARK: - 歌词 / 封面

    public func lyric(_ track: Track) async throws -> LyricInfo {
        guard track.source == .wy else { return try await base.lyric(track) }
        do {
            return try await client.lyric(id: track.songmid)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await base.lyric(track)
        }
    }

    public func picURL(_ track: Track) async throws -> URL {
        if let raw = track.rawPayload["picUrl"] as? String, let url = URL(string: raw), url.host != nil {
            return url
        }
        return try await base.picURL(track)
    }

    // MARK: - 歌手

    public func searchArtists(_ keyword: String, source: MusicSource, page: Int) async throws -> ArtistSearchPage {
        try await searchArtists(keyword, source: source, page: page, limit: 20)
    }

    public func searchArtists(_ keyword: String, source: MusicSource, page: Int, limit: Int) async throws -> ArtistSearchPage {
        guard source == .wy else {
            return try await base.searchArtists(keyword, source: source, page: page, limit: limit)
        }
        let offset = max(0, (max(1, page) - 1) * limit)
        let result = try await client.searchArtists(keyword, limit: limit, offset: offset)
        return ArtistSearchPage(
            list: result.artists,
            total: result.total,
            source: source,
            page: page,
            limit: limit
        )
    }

    public func searchAlbums(_ keyword: String, source: MusicSource, page: Int, limit: Int) async throws -> AlbumPage {
        guard source == .wy else {
            return try await base.searchAlbums(keyword, source: source, page: page, limit: limit)
        }
        let offset = max(0, (max(1, page) - 1) * limit)
        let result = try await client.searchAlbums(keyword, limit: limit, offset: offset)
        return AlbumPage(list: result.albums, total: result.total, source: .wy)
    }

    public func artistDetail(_ artist: ArtistSummary) async throws -> ArtistSummary {
        guard artist.source == .wy else { return try await base.artistDetail(artist) }
        let result = try await client.artist(id: artist.id)
        return result.artist
    }

    public func artistPopularTracks(_ artist: ArtistSummary) async throws -> [Track] {
        guard artist.source == .wy else { return try await base.artistPopularTracks(artist) }
        let result = try await client.artist(id: artist.id)
        return result.tracks
    }

    public func artistAlbums(_ artist: ArtistSummary, page: Int) async throws -> AlbumPage {
        guard artist.source == .wy else { return try await base.artistAlbums(artist, page: page) }
        let offset = max(0, (max(1, page) - 1) * 24)
        let albums = try await client.artistAlbums(id: artist.id, limit: 24, offset: offset)
        return AlbumPage(list: albums, total: artist.albumCount ?? albums.count, source: .wy)
    }

    // MARK: - 专辑

    public func albumTracks(_ album: AlbumSummary) async throws -> AlbumDetail {
        guard album.source == .wy else { return try await base.albumTracks(album) }
        return try await client.album(id: album.id)
    }

    // MARK: - 详情补全

    public func trackDetail(_ track: Track) async throws -> Track {
        guard track.source == .wy else { return try await base.trackDetail(track) }
        if let detail = try? await client.songDetail(ids: [track.songmid]).first {
            return detail
        }
        return try await base.trackDetail(track)
    }
}

/// 直接调用网易云播放接口，拿到请求档位对应的真实地址。
public final class NetEasePlaybackResolver: PlaybackURLRefreshing, PlaybackQualityReporting, @unchecked Sendable {
    private let client: NetEaseWebClient
    private let lock = NSLock()
    private var lastResolvedQuality: Quality?

    public init(client: NetEaseWebClient) {
        self.client = client
    }

    public func consumeLastResolvedQuality() -> Quality? {
        lock.lock()
        defer { lock.unlock() }
        let value = lastResolvedQuality
        lastResolvedQuality = nil
        return value
    }

    private func record(_ quality: Quality) {
        lock.lock()
        lastResolvedQuality = quality
        lock.unlock()
    }

    public func supportsPlayback(of source: MusicSource) -> Bool { source == .wy }

    public func musicURL(for track: Track, quality: Quality) async throws -> URL {
        try await resolve(track: track, quality: quality)
    }

    public func refreshMusicURL(for track: Track, quality: Quality) async throws -> URL {
        try await resolve(track: track, quality: quality)
    }

    private func resolve(track: Track, quality: Quality) async throws -> URL {
        guard track.source == .wy else {
            throw SourceError.source(message: "当前解析器只支持网易云音源")
        }
        let request = Self.request(for: quality)
        let (url, actual) = try await client.playableURL(id: track.songmid, level: request.level, encodeType: request.encodeType)
        let actualQuality = Self.quality(from: actual)
        guard actualQuality.rank >= quality.rank else {
            throw SourceError.source(message: "该音质不可用，实际返回 \(actualQuality.title)")
        }
        record(actualQuality)
        return url
    }

    static func request(for quality: Quality) -> (level: String, encodeType: String) {
        switch quality {
        case .standard: ("standard", "mp3")
        case .high: ("exhigh", "mp3")
        case .lossless: ("lossless", "flac")
        case .hiRes: ("hires", "flac")
        case .master: ("jymaster", "flac")
        }
    }

    static func quality(from value: NetEaseWebClient.TrackQuality) -> Quality {
        let level = value.level.lowercased()
        // `jyeffect` 是 SVIP 空间的 3 Mbps 档（母带/全景声回退档），必须算作 master，
        // 否则会被误判成 lossless 而降级到 944 kbps。
        if ["jymaster", "sky", "vivid", "jyeffect"].contains(level) || value.bitrate >= 2_000_000 { return .master }
        if level == "hires" || value.bitrate >= 1_500_000 { return .hiRes }
        if level == "lossless" || value.bitrate >= 700_000 { return .lossless }
        if level == "exhigh" || value.bitrate >= 300_000 { return .high }
        return .standard
    }
}
