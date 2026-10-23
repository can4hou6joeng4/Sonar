import Foundation

/// 逐曲歌词偏移（秒）：正值表示歌词整体延后显示。
enum LyricsOffsetStore {
    private static let key = "sonar.lyrics.offset"
    static let step: TimeInterval = 0.5
    static let range: ClosedRange<TimeInterval> = -5 ... 5

    static func offset(for musicID: String?) -> TimeInterval {
        guard let musicID, !musicID.isEmpty else { return 0 }
        let stored = UserDefaults.standard.dictionary(forKey: key) as? [String: Double]
        return stored?[musicID] ?? 0
    }

    @discardableResult
    static func adjust(_ musicID: String?, by delta: TimeInterval) -> TimeInterval {
        guard let musicID, !musicID.isEmpty else { return 0 }
        var stored = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        let next = min(max((stored[musicID] ?? 0) + delta, range.lowerBound), range.upperBound)
        if abs(next) < 0.001 {
            stored.removeValue(forKey: musicID)
        } else {
            stored[musicID] = next
        }
        UserDefaults.standard.set(stored, forKey: key)
        return next
    }

    static func reset(_ musicID: String?) {
        guard let musicID, !musicID.isEmpty else { return }
        var stored = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
        stored.removeValue(forKey: musicID)
        UserDefaults.standard.set(stored, forKey: key)
    }
}
