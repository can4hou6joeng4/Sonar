import Foundation

struct KaraokeToken: Equatable, Sendable, Identifiable {
    let id: Int
    let text: String
    let startMs: Int
    let endMs: Int

    func progress(atMilliseconds milliseconds: Double) -> Double {
        guard milliseconds > Double(startMs) else { return 0 }
        guard milliseconds < Double(endMs) else { return 1 }
        return (milliseconds - Double(startMs)) / Double(max(1, endMs - startMs))
    }
}

struct KaraokeLine: Equatable, Sendable, Identifiable {
    let id: Int
    let startMs: Int
    let endMs: Int
    let text: String
    let translation: String?
    let romanization: String?
    let tokens: [KaraokeToken]
}

struct KaraokeLyrics: Equatable, Sendable {
    private static let translationToleranceMs = 120.0
    private static let fallbackLastLineDurationMs = 4_000
    private static let fallbackSweepRatio = 0.88

    private static let timestampExpression = try! NSRegularExpression(
        pattern: #"\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]"#
    )
    private static let timedTokenExpression = try! NSRegularExpression(
        pattern: #"<(\d+),(\d+)>([^<]*)"#
    )
    private static let fallbackTokenExpression = try! NSRegularExpression(
        pattern: #"[぀-ヿ㐀-䶿一-鿿]|[^぀-ヿ㐀-䶿一-鿿\s]+\s*|\s+"#
    )

    let lines: [KaraokeLine]

    var hasTranslation: Bool {
        lines.contains { $0.translation?.isEmpty == false }
    }

    var hasRomanization: Bool {
        lines.contains { $0.romanization?.isEmpty == false }
    }

    init(lines: [KaraokeLine] = []) {
        self.lines = lines
    }

    init(info: LyricInfo) {
        let translations = LRCParser.parse(info.tlyric ?? "")
        let romanizations = LRCParser.parse(info.rlyric ?? "")
        let parsed = Self.parseTimed(info.lxlyric)
            ?? Self.synthesizeFallback(info.lyric)

        lines = parsed.enumerated().map { index, rawLine in
            KaraokeLine(
                id: index,
                startMs: rawLine.startMs,
                endMs: rawLine.endMs,
                text: rawLine.text,
                translation: Self.nearestText(
                    to: rawLine.startMs,
                    in: translations,
                    toleranceMs: Self.translationToleranceMs
                ),
                romanization: Self.nearestText(
                    to: rawLine.startMs,
                    in: romanizations,
                    toleranceMs: Self.translationToleranceMs
                ),
                tokens: rawLine.tokens.enumerated().map { tokenIndex, token in
                    KaraokeToken(
                        id: tokenIndex,
                        text: token.text,
                        startMs: token.startMs,
                        endMs: token.endMs
                    )
                }
            )
        }
    }

    func currentIndex(at time: TimeInterval) -> Int? {
        guard !lines.isEmpty else { return nil }
        let milliseconds = max(0, time) * 1_000
        var low = 0
        var high = lines.count
        while low < high {
            let middle = (low + high) / 2
            if Double(lines[middle].startMs) <= milliseconds {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return max(0, low - 1)
    }

    private static func parseTimed(_ text: String?) -> [RawLine]? {
        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        var parsed: [(order: Int, line: RawLine)] = []
        var timestampLineCount = 0

        for (order, sourceLine) in text.components(separatedBy: .newlines).enumerated() {
            let line = sourceLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            let fullRange = NSRange(line.startIndex..<line.endIndex, in: line)
            let timestamps = timestampExpression.matches(in: line, range: fullRange)
            guard !timestamps.isEmpty else { continue }
            timestampLineCount += 1

            guard let contentStart = timestamps.map({ NSMaxRange($0.range) }).max(),
                  let contentRange = Range(NSRange(location: contentStart, length: fullRange.length - contentStart), in: line) else {
                return nil
            }
            let content = String(line[contentRange])
            guard let relativeTokens = parseTimedTokens(content) else { return nil }

            for timestamp in timestamps {
                guard let startMs = timestampMilliseconds(timestamp, in: line) else { return nil }
                let tokens = relativeTokens.map { token in
                    RawToken(
                        text: token.text,
                        startMs: startMs + token.startMs,
                        endMs: startMs + token.endMs
                    )
                }
                parsed.append((
                    order,
                    RawLine(
                        startMs: startMs,
                        endMs: max(startMs + 1, tokens.map(\.endMs).max() ?? startMs + 1),
                        text: tokens.map(\.text).joined().trimmingCharacters(in: .whitespaces),
                        tokens: tokens
                    )
                ))
            }
        }

        guard timestampLineCount > 0, !parsed.isEmpty else { return nil }
        let sorted = parsed.sorted { lhs, rhs in
            lhs.line.startMs == rhs.line.startMs ? lhs.order < rhs.order : lhs.line.startMs < rhs.line.startMs
        }.map(\.line)

        return sorted.enumerated().map { index, line in
            let nextStart = sorted.indices.contains(index + 1) ? sorted[index + 1].startMs : nil
            return RawLine(
                startMs: line.startMs,
                endMs: max(line.startMs + 1, nextStart ?? line.endMs),
                text: line.text,
                tokens: line.tokens
            )
        }
    }

    private static func parseTimedTokens(_ content: String) -> [RawToken]? {
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        let matches = timedTokenExpression.matches(in: content, range: range)
        guard !matches.isEmpty else { return nil }

        var cursor = 0
        var tokens: [RawToken] = []
        for match in matches {
            guard match.range.location == cursor,
                  let offset = integer(match, group: 1, in: content),
                  let duration = integer(match, group: 2, in: content),
                  let textRange = Range(match.range(at: 3), in: content) else {
                return nil
            }
            let tokenText = String(content[textRange])
            guard !tokenText.isEmpty else { return nil }
            tokens.append(RawToken(
                text: tokenText,
                startMs: offset,
                endMs: offset + max(1, duration)
            ))
            cursor = NSMaxRange(match.range)
        }

        guard cursor == range.length,
              !tokens.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return tokens
    }

    private static func synthesizeFallback(_ lyric: String) -> [RawLine] {
        let lines = LRCParser.parse(lyric)
        return lines.enumerated().map { index, line in
            let startMs = Int((line.time * 1_000).rounded())
            let nextMs = lines.indices.contains(index + 1)
                ? Int((lines[index + 1].time * 1_000).rounded())
                : startMs + fallbackLastLineDurationMs
            let endMs = max(startMs + 1, nextMs)
            let tokenTexts = splitFallbackTokens(line.text)
            let weights = tokenTexts.map(tokenWeight)
            let totalWeight = weights.reduce(0, +)
            let sweepDuration = Double(endMs - startMs) * fallbackSweepRatio
            var cursor = Double(startMs)

            let tokens = zip(tokenTexts, weights).map { text, weight in
                let duration = totalWeight > 0 ? sweepDuration * weight / totalWeight : 0
                let token = RawToken(
                    text: text,
                    startMs: Int(cursor.rounded()),
                    endMs: Int((cursor + max(1, duration)).rounded())
                )
                cursor += duration
                return token
            }

            return RawLine(
                startMs: startMs,
                endMs: endMs,
                text: line.text,
                tokens: tokens
            )
        }
    }

    private static func splitFallbackTokens(_ text: String) -> [String] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = fallbackTokenExpression.matches(in: text, range: range)
        let tokens = matches.compactMap { match -> String? in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
        return tokens.isEmpty ? [text] : tokens
    }

    private static func tokenWeight(_ token: String) -> Double {
        if token.unicodeScalars.allSatisfy({ CharacterSet.whitespacesAndNewlines.contains($0) }) {
            return 0.25
        }
        if token.unicodeScalars.contains(where: isCJK) {
            return 1
        }
        let length = token.trimmingCharacters(in: .whitespacesAndNewlines).count
        return 0.5 + 0.11 * Double(length)
    }

    private static func isCJK(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.value {
        case 0x3040...0x30FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
             0xF900...0xFAFF, 0xFF66...0xFF9F:
            return true
        default:
            return false
        }
    }

    private static func nearestText(
        to milliseconds: Int,
        in lines: [LyricLine],
        toleranceMs: Double
    ) -> String? {
        lines
            .map { line in (line, abs(line.time * 1_000 - Double(milliseconds))) }
            .filter { $0.1 <= toleranceMs + 0.001 }
            .min { lhs, rhs in lhs.1 < rhs.1 }?
            .0.text
    }

    private static func timestampMilliseconds(_ match: NSTextCheckingResult, in text: String) -> Int? {
        guard let minute = integer(match, group: 1, in: text),
              let second = integer(match, group: 2, in: text) else {
            return nil
        }
        let fraction = fractionMilliseconds(match, group: 3, in: text)
        return (minute * 60 + second) * 1_000 + fraction
    }

    private static func integer(_ match: NSTextCheckingResult, group: Int, in text: String) -> Int? {
        guard let range = Range(match.range(at: group), in: text) else { return nil }
        return Int(text[range])
    }

    private static func fractionMilliseconds(_ match: NSTextCheckingResult, group: Int, in text: String) -> Int {
        guard let range = Range(match.range(at: group), in: text),
              !range.isEmpty,
              let value = Int(text[range]) else {
            return 0
        }
        switch text[range].count {
        case 1: return value * 100
        case 2: return value * 10
        default: return value
        }
    }
}

private extension KaraokeLyrics {
    struct RawToken {
        let text: String
        let startMs: Int
        let endMs: Int
    }

    struct RawLine {
        let startMs: Int
        let endMs: Int
        let text: String
        let tokens: [RawToken]
    }
}
