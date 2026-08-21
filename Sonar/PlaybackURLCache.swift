import Foundation

public actor PlaybackURLCache {
    public struct Key: Hashable, Sendable {
        public let musicID: String
        public let quality: Quality

        public init(track: Track, quality: Quality) {
            musicID = "\(track.source.rawValue)_\(track.songmid)"
            self.quality = quality
        }
    }

    private struct Entry: Sendable {
        let url: URL
        let actualQuality: Quality
        let expiresAt: Date
    }

    private var entries: [Key: Entry] = [:]
    private let ttl: TimeInterval
    private let now: @Sendable () -> Date

    public init(ttl: TimeInterval = 20 * 60, now: @escaping @Sendable () -> Date = { Date() }) {
        self.ttl = ttl
        self.now = now
    }

    public func value(for key: Key) -> URL? {
        guard let entry = entries[key] else { return nil }
        guard entry.expiresAt > now(), entry.actualQuality.rank >= key.quality.rank else {
            entries[key] = nil
            return nil
        }
        return entry.url
    }

    public func insert(_ url: URL, actualQuality: Quality, for key: Key) {
        guard actualQuality.rank >= key.quality.rank else { return }
        entries[key] = Entry(url: url, actualQuality: actualQuality, expiresAt: now().addingTimeInterval(ttl))
    }

    public func removeAll() {
        entries.removeAll()
    }
}

extension Quality {
    fileprivate var rank: Int {
        switch self {
        case .standard: 0
        case .high: 1
        case .lossless: 2
        case .hiRes: 3
        }
    }
}
