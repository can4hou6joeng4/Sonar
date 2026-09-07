import Foundation
import CryptoKit
import UIKit
import ImageIO

public protocol ArtworkHTTPClient: Sendable {
    func data(from url: URL) async throws -> Data
}

public struct URLSessionArtworkHTTPClient: ArtworkHTTPClient {
    public init() {}

    public func data(from url: URL) async throws -> Data {
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else {
                throw SourceError.source(message: "封面请求返回异常")
            }
            return data
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as SourceError {
            throw error
        } catch {
            throw SourceError.network(underlying: error)
        }
    }
}

public actor ArtworkService {
    public struct Limits: Sendable {
        public let memoryBytes: Int
        public let diskBytes: Int
        public let maximumPixelDimension: Int

        public init(
            memoryBytes: Int = 32 * 1024 * 1024,
            diskBytes: Int = 128 * 1024 * 1024,
            maximumPixelDimension: Int = 1200
        ) {
            self.memoryBytes = max(0, memoryBytes)
            self.diskBytes = max(0, diskBytes)
            self.maximumPixelDimension = max(1, maximumPixelDimension)
        }
    }

    private struct MemoryEntry {
        let image: UIImage
        let cost: Int
        let expiresAt: Date
        var access: UInt64
    }

    private struct Pending {
        let id: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: CheckedContinuation<UIImage, Error>]
    }

    private let sourceRuntime: SourceRuntime
    private let client: ArtworkHTTPClient
    private let cacheDirectory: URL
    private let ttl: TimeInterval
    private let limits: Limits
    private var memoryCache: [String: MemoryEntry] = [:]
    private var memoryBytes = 0
    private var access: UInt64 = 0
    private var pending: [String: Pending] = [:]

    public init(
        sourceRuntime: SourceRuntime,
        client: ArtworkHTTPClient = URLSessionArtworkHTTPClient(),
        cacheDirectory: URL? = nil,
        ttl: TimeInterval = 7 * 24 * 60 * 60,
        limits: Limits = Limits()
    ) throws {
        self.sourceRuntime = sourceRuntime
        self.client = client
        self.ttl = max(0, ttl)
        self.limits = limits
        if let cacheDirectory {
            self.cacheDirectory = cacheDirectory
        } else {
            self.cacheDirectory = try FileManager.default.url(
                for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            ).appendingPathComponent("Artwork", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
        Self.trimDisk(directory: self.cacheDirectory, ttl: self.ttl, limit: limits.diskBytes, now: Date())
    }

    public func image(for track: Track, now: Date = Date()) async throws -> UIImage {
        try Task.checkCancellation()
        let key = track.musicID
        trimMemory(now: now)
        if var cached = memoryCache[key] {
            access &+= 1
            cached.access = access
            memoryCache[key] = cached
            return cached.image
        }
        Self.trimDisk(directory: cacheDirectory, ttl: ttl, limit: limits.diskBytes, now: now)
        let fileURL = cacheURL(for: key)
        if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let modified = attributes[.modificationDate] as? Date,
           now.timeIntervalSince(modified) < ttl,
           let data = try? Data(contentsOf: fileURL),
           let image = Self.downsample(data, maximumPixelDimension: limits.maximumPixelDimension) {
            insertMemory(image, key: key, expiresAt: modified.addingTimeInterval(ttl), now: now)
            return image
        }

        let waiterID = UUID()
        let image: UIImage = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                if pending[key] != nil {
                    pending[key]?.waiters[waiterID] = continuation
                    return
                }
                let requestID = UUID()
                let task = Task {
                    do {
                        let url = try await sourceRuntime.picURL(track)
                        try Task.checkCancellation()
                        let data = try await client.data(from: url)
                        try Task.checkCancellation()
                        guard let image = Self.downsample(data, maximumPixelDimension: limits.maximumPixelDimension) else {
                            throw SourceError.source(message: "封面数据无法解码")
                        }
                        finish(key: key, requestID: requestID, result: .success(image), now: now)
                    } catch {
                        finish(key: key, requestID: requestID, result: .failure(error), now: now)
                    }
                }
                pending[key] = Pending(id: requestID, task: task, waiters: [waiterID: continuation])
            }
        } onCancel: {
            Task { await self.cancelWaiter(key: key, waiterID: waiterID) }
        }
        try Task.checkCancellation()
        return image
    }

    public func accentHex(for track: Track, now: Date = Date()) async throws -> String? {
        let image = try await image(for: track, now: now)
        try Task.checkCancellation()
        return ArtworkPalette.accentHex(from: image)
    }

    public func removeCachedArtwork(for track: Track) throws {
        let key = track.musicID
        removeMemory(key)
        if let request = pending.removeValue(forKey: key) {
            request.task.cancel()
            for waiter in request.waiters.values { waiter.resume(throwing: CancellationError()) }
        }
        try? FileManager.default.removeItem(at: cacheURL(for: key))
    }

    // Internal accounting also lets tests assert actual byte limits and consumer ownership.
    func cacheUsage() -> (memoryBytes: Int, memoryEntries: Int, pendingConsumers: Int) {
        (memoryBytes, memoryCache.count, pending.values.reduce(0) { $0 + $1.waiters.count })
    }

    private func cancelWaiter(key: String, waiterID: UUID) {
        guard let continuation = pending[key]?.waiters.removeValue(forKey: waiterID) else { return }
        continuation.resume(throwing: CancellationError())
        if pending[key]?.waiters.isEmpty == true {
            pending.removeValue(forKey: key)?.task.cancel()
        }
    }

    private func finish(key: String, requestID: UUID, result: Result<UIImage, Error>, now: Date) {
        guard let request = pending[key], request.id == requestID else { return }
        pending[key] = nil
        if case let .success(image) = result {
            insertMemory(image, key: key, expiresAt: now.addingTimeInterval(ttl), now: now)
            // Persist the downsampled image, not the original full-resolution response.
            if ttl > 0, limits.diskBytes > 0,
               let data = image.jpegData(compressionQuality: 0.9), data.count <= limits.diskBytes {
                let url = cacheURL(for: key)
                do {
                    try data.write(to: url, options: .atomic)
                    try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
                } catch {
                    // Artwork remains usable if the disposable cache cannot be written.
                }
            }
            Self.trimDisk(directory: cacheDirectory, ttl: ttl, limit: limits.diskBytes, now: now)
        }
        for waiter in request.waiters.values { waiter.resume(with: result) }
    }

    private func insertMemory(_ image: UIImage, key: String, expiresAt: Date, now: Date) {
        removeMemory(key)
        guard let cgImage = image.cgImage else { return }
        let cost = cgImage.bytesPerRow * cgImage.height
        guard cost <= limits.memoryBytes, expiresAt > now else { return }
        access &+= 1
        memoryCache[key] = MemoryEntry(image: image, cost: cost, expiresAt: expiresAt, access: access)
        memoryBytes += cost
        trimMemory(now: now)
    }

    private func trimMemory(now: Date) {
        for key in memoryCache.keys.filter({ memoryCache[$0]!.expiresAt <= now }) { removeMemory(key) }
        while memoryBytes > limits.memoryBytes,
              let oldest = memoryCache.min(by: { $0.value.access < $1.value.access })?.key {
            removeMemory(oldest)
        }
    }

    private func removeMemory(_ key: String) {
        if let old = memoryCache.removeValue(forKey: key) { memoryBytes -= old.cost }
    }

    private static func downsample(_ data: Data, maximumPixelDimension: Int) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension,
              ] as CFDictionary) else { return nil }
        return UIImage(cgImage: image)
    }

    private static func trimDisk(directory: URL, ttl: TimeInterval, limit: Int, now: Date) {
        let manager = FileManager.default
        let files = (try? manager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        )) ?? []
        var retained: [(url: URL, size: Int, modified: Date)] = []
        for url in files where url.pathExtension == "img" {
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]),
                  values.isRegularFile == true else { continue }
            let modified = values.contentModificationDate ?? .distantPast
            let size = values.fileSize ?? 0
            if now.timeIntervalSince(modified) >= ttl || size > limit || limit == 0 {
                try? manager.removeItem(at: url)
            } else {
                retained.append((url, size, modified))
            }
        }
        var total = retained.reduce(0) { $0 + $1.size }
        for file in retained.sorted(by: { $0.modified == $1.modified ? $0.url.path < $1.url.path : $0.modified < $1.modified }) {
            guard total > limit else { break }
            do {
                try manager.removeItem(at: file.url)
                total -= file.size
            } catch { continue }
        }
    }

    private func cacheURL(for key: String) -> URL {
        let digest = ArtworkCacheHash.hexDigest(Data(key.utf8))
        return cacheDirectory.appendingPathComponent("\(digest).img")
    }
}

private enum ArtworkCacheHash {
    static func hexDigest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
