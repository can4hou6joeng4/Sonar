import Foundation
import CryptoKit
import UIKit

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
        } catch let error as SourceError {
            throw error
        } catch {
            throw SourceError.network(underlying: error)
        }
    }
}

public actor ArtworkService {
    private let sourceRuntime: SourceRuntime
    private let client: ArtworkHTTPClient
    private let cacheDirectory: URL
    private let ttl: TimeInterval
    private var memoryCache: [String: UIImage] = [:]

    public init(
        sourceRuntime: SourceRuntime,
        client: ArtworkHTTPClient = URLSessionArtworkHTTPClient(),
        cacheDirectory: URL? = nil,
        ttl: TimeInterval = 7 * 24 * 60 * 60
    ) throws {
        self.sourceRuntime = sourceRuntime
        self.client = client
        self.ttl = max(0, ttl)
        if let cacheDirectory {
            self.cacheDirectory = cacheDirectory
        } else {
            let directory = try FileManager.default.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appendingPathComponent("Artwork", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            self.cacheDirectory = directory
        }
        try FileManager.default.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)
    }

    public func image(for track: Track, now: Date = Date()) async throws -> UIImage {
        let key = track.musicID
        if let cached = memoryCache[key] { return cached }
        let fileURL = cacheURL(for: key)
        if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           let modified = attributes[.modificationDate] as? Date,
           now.timeIntervalSince(modified) <= ttl,
           let data = try? Data(contentsOf: fileURL),
           let image = UIImage(data: data) {
            memoryCache[key] = image
            return image
        }

        let url = try await sourceRuntime.picURL(track)
        let data = try await client.data(from: url)
        guard let image = UIImage(data: data) else {
            throw SourceError.source(message: "封面数据无法解码")
        }
        try data.write(to: fileURL, options: .atomic)
        memoryCache[key] = image
        return image
    }

    public func accentHex(for track: Track, now: Date = Date()) async throws -> String? {
        let image = try await image(for: track, now: now)
        return ArtworkPalette.accentHex(from: image)
    }

    public func removeCachedArtwork(for track: Track) throws {
        memoryCache[track.musicID] = nil
        try? FileManager.default.removeItem(at: cacheURL(for: track.musicID))
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
