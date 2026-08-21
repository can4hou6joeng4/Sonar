import Foundation

public struct LyricLine: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let time: TimeInterval
    public let text: String

    public init(id: UUID = UUID(), time: TimeInterval, text: String) {
        self.id = id
        self.time = time
        self.text = text
    }
}

public struct LyricsDocument: Equatable, Sendable {
    public let lines: [LyricLine]
    public let translatedLines: [LyricLine]

    public init(lines: [LyricLine], translatedLines: [LyricLine] = []) {
        self.lines = lines.sorted { lhs, rhs in
            lhs.time == rhs.time ? lhs.id.uuidString < rhs.id.uuidString : lhs.time < rhs.time
        }
        self.translatedLines = translatedLines.sorted { lhs, rhs in
            lhs.time == rhs.time ? lhs.id.uuidString < rhs.id.uuidString : lhs.time < rhs.time
        }
    }

    public func currentIndex(at time: TimeInterval) -> Int? {
        guard !lines.isEmpty else { return nil }
        let clamped = max(0, time)
        var low = 0
        var high = lines.count
        while low < high {
            let middle = (low + high) / 2
            if lines[middle].time <= clamped {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low == 0 ? nil : low - 1
    }

    public func line(at index: Int) -> LyricLine? {
        lines.indices.contains(index) ? lines[index] : nil
    }

    public func translation(for line: LyricLine, tolerance: TimeInterval = 0.08) -> String? {
        translatedLines.first { abs($0.time - line.time) <= tolerance }?.text
    }
}

public enum LRCParser {
    private static let timestamp = try! NSRegularExpression(pattern: #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#)

    public static func parse(_ text: String) -> [LyricLine] {
        var result: [LyricLine] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            let matches = timestamp.matches(in: line, range: range)
            guard !matches.isEmpty else { continue }
            let contentStart = matches.reduce(0) { max($0, $1.range.location + $1.range.length) }
            let content = String(line.dropFirst(contentStart)).trimmingCharacters(in: .whitespaces)
            guard !content.isEmpty else { continue }
            for match in matches {
                guard let minute = integer(match, group: 1, in: line),
                      let second = integer(match, group: 2, in: line) else { continue }
                let fraction = fractionValue(match, group: 3, in: line)
                result.append(LyricLine(time: TimeInterval(minute * 60 + second) + fraction, text: content))
            }
        }
        return result.sorted { lhs, rhs in
            lhs.time == rhs.time ? lhs.id.uuidString < rhs.id.uuidString : lhs.time < rhs.time
        }
    }

    public static func document(lyric: String, translated: String? = nil) -> LyricsDocument {
        LyricsDocument(lines: parse(lyric), translatedLines: parse(translated ?? ""))
    }

    private static func integer(_ match: NSTextCheckingResult, group: Int, in text: String) -> Int? {
        guard let range = Range(match.range(at: group), in: text) else { return nil }
        return Int(text[range])
    }

    private static func fractionValue(_ match: NSTextCheckingResult, group: Int, in text: String) -> TimeInterval {
        guard let range = Range(match.range(at: group), in: text), !range.isEmpty,
              let value = Double(text[range]) else { return 0 }
        let digits = text[range].count
        return value / pow(10, Double(digits))
    }
}
