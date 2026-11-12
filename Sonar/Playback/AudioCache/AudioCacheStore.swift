import CryptoKit
import Foundation

extension Notification.Name {
    static let sonarAudioCacheDidChange = Notification.Name("sonar.audioCache.didChange")
}

struct CachedAudio: Codable, Sendable, Equatable, Identifiable {
    let musicID: String
    let quality: Quality
    var requestedQualities: Set<Quality>
    let fileName: String
    var byteCount: Int64
    var sha256: String?
    let createdAt: Date
    var lastAccessedAt: Date
    let title: String
    let artist: String
    let album: String

    var id: String { "\(musicID)|\(quality.rawValue)" }

    init(
        musicID: String, quality: Quality, requestedQualities: Set<Quality>,
        fileName: String, byteCount: Int64, sha256: String?, createdAt: Date,
        lastAccessedAt: Date, title: String, artist: String, album: String
    ) {
        self.musicID = musicID
        self.quality = quality
        self.requestedQualities = requestedQualities
        self.fileName = fileName
        self.byteCount = byteCount
        self.sha256 = sha256
        self.createdAt = createdAt
        self.lastAccessedAt = lastAccessedAt
        self.title = title
        self.artist = artist
        self.album = album
    }

    private enum CodingKeys: String, CodingKey {
        case musicID, quality, requestedQualities, fileName, byteCount, sha256
        case createdAt, lastAccessedAt, title, artist, album
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        musicID = try values.decode(String.self, forKey: .musicID)
        quality = try values.decode(Quality.self, forKey: .quality)
        requestedQualities = try values.decodeIfPresent(Set<Quality>.self, forKey: .requestedQualities) ?? [quality]
        fileName = try values.decode(String.self, forKey: .fileName)
        byteCount = try values.decode(Int64.self, forKey: .byteCount)
        sha256 = try values.decodeIfPresent(String.self, forKey: .sha256)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        lastAccessedAt = try values.decode(Date.self, forKey: .lastAccessedAt)
        title = try values.decode(String.self, forKey: .title)
        artist = try values.decode(String.self, forKey: .artist)
        album = try values.decode(String.self, forKey: .album)
    }
}

/// 音频与原子索引独立于歌单数据库。空间不足时停止新增，不淘汰已有缓存。
actor AudioCacheStore {
    private struct Index: Codable {
        var version: Int
        var entries: [CachedAudio]
    }

    private struct Fingerprint: Equatable {
        let size: Int64
        let modifiedAt: Date
    }

    enum StoreError: LocalizedError, Sendable {
        case invalidFile

        var errorDescription: String? { "音频缓存文件为空或已损坏" }
    }

    private static let indexVersion = 2
    private static let reserveBytes: Int64 = 1_000_000_000

    private let directory: URL
    private let indexURL: URL
    private let fileManager: FileManager
    private let capacity: (@Sendable () -> Int64)?
    private var entries: [String: CachedAudio] = [:]
    private var verifiedFiles: [String: Fingerprint] = [:]
    private var loaded = false
    private var saveTask: Task<Void, Never>?
    private var lastError: String?

    init(
        directory: URL? = nil,
        fileManager: FileManager = .default,
        availableCapacity: (@Sendable () -> Int64)? = nil
    ) {
        self.fileManager = fileManager
        self.capacity = availableCapacity
        let resolved: URL
        if let directory {
            resolved = directory
        } else if let base = try? fileManager.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) {
            resolved = base.appendingPathComponent("Sonar/AudioCache", isDirectory: true)
        } else {
            resolved = fileManager.temporaryDirectory.appendingPathComponent("Sonar/AudioCache", isDirectory: true)
        }
        try? fileManager.createDirectory(at: resolved, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = resolved
        try? mutableDirectory.setResourceValues(values)
        self.directory = resolved
        self.indexURL = resolved.appendingPathComponent("index.json", isDirectory: false)
    }

    // MARK: - 查询

    func cachedEntry(for track: Track, preferred: Quality, allowLowerQuality: Bool) -> CachedAudio? {
        prepare()
        let candidates = entries.values.filter {
            $0.musicID == track.musicID && (
                allowLowerQuality || $0.quality.rank >= preferred.rank || $0.requestedQualities.contains(preferred)
            )
        }.sorted { $0.quality.rank > $1.quality.rank }
        for candidate in candidates {
            guard var entry = validated(candidate) else { continue }
            entry.lastAccessedAt = Date()
            entries[entry.id] = entry
            scheduleSave()
            return entry
        }
        return nil
    }

    func fileURL(for entry: CachedAudio) -> URL {
        directory.appendingPathComponent(entry.fileName, isDirectory: false)
    }

    func cachedURL(for track: Track, preferred: Quality, allowLowerQuality: Bool) -> (url: URL, quality: Quality)? {
        guard let entry = cachedEntry(for: track, preferred: preferred, allowLowerQuality: allowLowerQuality) else {
            return nil
        }
        return (fileURL(for: entry), entry.quality)
    }

    func hasSpaceForDownload() -> Bool { availableCapacity() > Self.reserveBytes }

    func totalBytes() -> Int64 {
        prepare()
        pruneMissingFiles()
        // 未提交成功或删除失败的音频也计入占用，清空操作会遍历整个缓存目录。
        return cacheFiles().filter { !$0.lastPathComponent.hasSuffix(".json") }.reduce(0) {
            $0 + (fingerprint(at: $1)?.size ?? 0)
        }
    }

    func count() -> Int {
        prepare()
        pruneMissingFiles()
        return entries.count
    }

    func allEntries() -> [CachedAudio] {
        prepare()
        pruneMissingFiles()
        return entries.values.sorted { $0.lastAccessedAt > $1.lastAccessedAt }
    }

    func lastErrorMessage() -> String? { lastError }

    /// 解析后若已有该实际档位，只补记这次请求，避免再次下载相同文件。
    func rememberRequest(_ requestedQuality: Quality, for cached: CachedAudio) throws -> Bool {
        prepare()
        try Task.checkCancellation()
        guard let current = entries[cached.id], current.fileName == cached.fileName,
              var entry = validated(current) else { return false }
        guard entry.requestedQualities.insert(requestedQuality).inserted else { return true }
        do {
            try writeSidecar(entry)
            var updated = entries
            updated[entry.id] = entry
            try persist(updated)
            entries = updated
            lastError = nil
            postChanged()
            return true
        } catch {
            try? writeSidecar(current)
            // 文件已验证有效；索引写入失败只影响下次启动的别名恢复，不应重新下载整首。
            entries[entry.id] = entry
            report(error)
            return true
        }
    }

    // MARK: - 写入

    @discardableResult
    func install(
        tempURL: URL, track: Track, actualQuality: Quality, fileExtension: String,
        requestedQuality: Quality? = nil
    ) throws -> CachedAudio {
        prepare()
        try Task.checkCancellation()
        guard let source = fingerprint(at: tempURL), source.size > 0 else { throw StoreError.invalidFile }
        let digest = try checksum(at: tempURL)
        try Task.checkCancellation()
        let ext = Self.sanitizedExtension(fileExtension, quality: actualQuality)
        // 每次安装都是新版本，旧播放项的失败通知不能误删新音频。
        let destination = directory.appendingPathComponent("\(UUID().uuidString).\(ext)")
        let key = "\(track.musicID)|\(actualQuality.rawValue)"
        let previous = entries[key]
        var requested = previous?.requestedQualities ?? []
        requested.insert(requestedQuality ?? actualQuality)
        let now = Date()
        let entry = CachedAudio(
            musicID: track.musicID, quality: actualQuality, requestedQualities: requested,
            fileName: destination.lastPathComponent, byteCount: source.size, sha256: digest,
            createdAt: now, lastAccessedAt: now, title: track.title, artist: track.artist, album: track.album
        )
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.moveItem(at: tempURL, to: destination)
            try Task.checkCancellation()
            try writeSidecar(entry)
            var updated = entries
            updated[key] = entry
            try Task.checkCancellation()
            try persist(updated)
            entries = updated
            verifiedFiles[entry.fileName] = fingerprint(at: destination)
            if let previous { deleteFiles(for: previous) }
            lastError = nil
            postChanged()
            return entry
        } catch {
            // 索引未提交时回滚新文件，已有版本保持可用。
            try? fileManager.removeItem(at: destination)
            try? fileManager.removeItem(at: sidecarURL(for: entry))
            report(error)
            throw error
        }
    }

    func invalidate(for track: Track, url: URL) throws {
        prepare()
        let targetName = url.lastPathComponent
        let targetPath = url.resolvingSymlinksInPath().standardizedFileURL
        let matching = entries.values.filter {
            guard $0.musicID == track.musicID else { return false }
            // 文件名是每次安装唯一的 UUID；同时兼容 /var 与 /private/var 等路径别名。
            return $0.fileName == targetName
                || fileURL(for: $0).resolvingSymlinksInPath().standardizedFileURL == targetPath
        }
        guard !matching.isEmpty else { return }
        for entry in matching {
            entries[entry.id] = nil
            deleteFiles(for: entry)
        }
        do {
            try persist(entries)
            lastError = nil
            postChanged()
        } catch {
            report(error)
            throw error
        }
    }

    func remove(musicID: String) throws {
        prepare()
        let removed = entries.values.filter { $0.musicID == musicID }
        for entry in removed {
            entries[entry.id] = nil
            deleteFiles(for: entry)
        }
        do {
            try persist(entries)
            postChanged()
        } catch {
            report(error)
            throw error
        }
    }

    func clear() throws {
        prepare()
        saveTask?.cancel()
        saveTask = nil
        // 先提交空索引；失败时不删除任何已有音频。
        do { try persist([:]) } catch {
            report(error)
            throw error
        }
        let previous = entries
        entries.removeAll()
        verifiedFiles.removeAll()
        var failure: Error?
        for url in cacheFiles() where url.standardizedFileURL != indexURL.standardizedFileURL {
            do { try fileManager.removeItem(at: url) } catch { failure = error }
        }
        // 删除失败仍有音频时继续记入索引，避免隐藏占用。
        for entry in previous.values where fingerprint(at: fileURL(for: entry)) != nil {
            entries[entry.id] = entry
        }
        if !entries.isEmpty {
            do { try persist(entries) } catch { failure = error }
        }
        if let failure {
            report(failure)
            throw failure
        }
        lastError = nil
        postChanged()
    }

    // MARK: - 索引与完整性

    private func prepare() {
        guard !loaded else { return }
        loaded = true
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try? Data(contentsOf: indexURL)
        let index = data.flatMap { try? decoder.decode(Index.self, from: $0) }
        let hasIndex = index.map { (1...Self.indexVersion).contains($0.version) } ?? false
        let recovered: [CachedAudio]
        if let index, hasIndex {
            recovered = index.entries
        } else {
            // 索引损坏时用逐文件元数据恢复；不删除仍完整的已缓存音频。
            recovered = cacheFiles().filter { $0.lastPathComponent != "index.json" && $0.pathExtension == "json" }
                .compactMap { url in
                    guard let data = try? Data(contentsOf: url) else { return nil }
                    return try? decoder.decode(CachedAudio.self, from: data)
                }
        }
        for entry in recovered.sorted(by: { $0.createdAt < $1.createdAt }) {
            guard Self.isSafeFileName(entry.fileName), let file = fingerprint(at: fileURL(for: entry)),
                  file.size > 0, entry.byteCount == file.size else { continue }
            entries[entry.id] = entry
        }
        if !hasIndex || index?.version != Self.indexVersion || entries.count != (index?.entries.count ?? 0) {
            do { try persist(entries) } catch { report(error) }
        }
        // 补齐旧索引的恢复元数据；失败不影响已经存在的音频。
        for entry in entries.values where !fileManager.fileExists(atPath: sidecarURL(for: entry).path) {
            do { try writeSidecar(entry) } catch { report(error) }
        }
    }

    private func validated(_ stored: CachedAudio) -> CachedAudio? {
        let url = fileURL(for: stored)
        guard Self.isSafeFileName(stored.fileName), let file = fingerprint(at: url),
              file.size > 0, file.size == stored.byteCount else {
            discardInvalid(stored)
            return nil
        }
        if stored.sha256 != nil, verifiedFiles[stored.fileName] == file { return stored }
        do {
            let digest = try checksum(at: url)
            guard stored.sha256 == nil || stored.sha256 == digest else {
                discardInvalid(stored)
                return nil
            }
            var entry = stored
            if entry.sha256 == nil {
                entry.sha256 = digest
                entries[entry.id] = entry
                // 文件本身已校验通过；索引暂写失败不应让可播放的缓存变成 miss。
                do {
                    try writeSidecar(entry)
                    try persist(entries)
                } catch {
                    report(error)
                }
            }
            verifiedFiles[entry.fileName] = file
            return entry
        } catch is CancellationError {
            return nil
        } catch {
            report(error)
            return nil
        }
    }

    private func pruneMissingFiles() {
        for entry in Array(entries.values) {
            guard let file = fingerprint(at: fileURL(for: entry)), file.size == entry.byteCount, file.size > 0 else {
                discardInvalid(entry)
                continue
            }
        }
    }

    private func discardInvalid(_ entry: CachedAudio) {
        entries[entry.id] = nil
        deleteFiles(for: entry)
        do { try persist(entries) } catch { report(error) }
        postChanged()
    }

    private func deleteFiles(for entry: CachedAudio) {
        verifiedFiles[entry.fileName] = nil
        guard Self.isSafeFileName(entry.fileName) else { return }
        for url in [fileURL(for: entry), sidecarURL(for: entry)] where fileManager.fileExists(atPath: url.path) {
            do { try fileManager.removeItem(at: url) } catch { report(error) }
        }
    }

    private func fingerprint(at url: URL) -> Fingerprint? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber,
              let modified = attributes[.modificationDate] as? Date else { return nil }
        return Fingerprint(size: size.int64Value, modifiedAt: modified)
    }

    private func checksum(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let bytes = try handle.read(upToCount: 1_048_576), !bytes.isEmpty {
            try Task.checkCancellation()
            hash.update(data: bytes)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func sidecarURL(for entry: CachedAudio) -> URL {
        directory.appendingPathComponent(entry.fileName + ".json")
    }

    private func writeSidecar(_ entry: CachedAudio) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(entry).write(to: sidecarURL(for: entry), options: .atomic)
    }

    private func persist(_ values: [String: CachedAudio]) throws {
        saveTask?.cancel()
        saveTask = nil
        let index = Index(version: Self.indexVersion, entries: values.values.sorted { $0.id < $1.id })
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(index).write(to: indexURL, options: .atomic)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            await self?.saveAccessDates()
        }
    }

    private func saveAccessDates() {
        do { try persist(entries) } catch { report(error) }
    }

    private func cacheFiles() -> [URL] {
        (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    }

    private func availableCapacity() -> Int64 {
        if let capacity { return capacity() }
        let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage ?? 0
    }

    private func report(_ error: Error) {
        guard !(error is CancellationError) else { return }
        lastError = "缓存存储失败：\(error.localizedDescription)"
        postChanged()
    }

    private func postChanged() {
        NotificationCenter.default.post(name: .sonarAudioCacheDidChange, object: nil)
    }

    private static func isSafeFileName(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." && !value.contains("/") && !value.contains("\\")
    }

    private static func sanitizedExtension(_ value: String, quality: Quality) -> String {
        let cleaned = String(value.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
        if !cleaned.isEmpty { return cleaned }
        return quality == .standard || quality == .high ? "mp3" : "flac"
    }
}
