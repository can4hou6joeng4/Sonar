import CoreGraphics
import Foundation

enum DiscoveryMasonry {
    static let ratios: [CGFloat] = [0.76, 0.88, 1, 1.12, 1.24]

    static func ratio(for key: String) -> CGFloat {
        // 只需要哈希对比例表长度的余数，逐步取模可避免长 key 溢出且与原公式等价。
        var remainder = 17 % ratios.count
        for codeUnit in key.utf16 {
            remainder = (37 * remainder + Int(codeUnit)) % ratios.count
        }
        return ratios[remainder]
    }

    static func columnAssignments(
        for keys: [String],
        columnWidth: CGFloat,
        columnCount: Int = 2,
        gap: CGFloat = 10
    ) -> [Int] {
        guard columnCount > 0 else { return [] }
        var heights = Array(repeating: CGFloat.zero, count: columnCount)
        return keys.map { key in
            let column = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            heights[column] += columnWidth / ratio(for: key) + 82 + gap
            return column
        }
    }
}
