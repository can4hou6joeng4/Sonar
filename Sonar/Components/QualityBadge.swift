import Foundation
import SwiftUI

struct TrackQualityOption: Identifiable, Equatable {
    let quality: Quality
    let sizeText: String

    var id: Quality { quality }

    static func available(for track: Track) -> [TrackQualityOption] {
        guard let rawTypes = track.rawPayload["types"] as? [[String: Any]] else { return [] }
        let values = rawTypes.compactMap { value -> TrackQualityOption? in
            guard let rawQuality = value["type"] as? String,
                  let quality = Quality(rawValue: rawQuality),
                  let size = value["size"] as? String,
                  !size.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return TrackQualityOption(quality: quality, sizeText: size)
        }
        return Quality.displayOrder.compactMap { quality in
            values.first { $0.quality == quality }
        }
    }
}

extension Quality {
    static let displayOrder: [Quality] = [.hiRes, .lossless, .high, .standard]

    var title: String {
        switch self {
        case .hiRes: "Hi-Res"
        case .lossless: "无损 FLAC"
        case .high: "高品质 320K"
        case .standard: "标准品质 128K"
        }
    }

    var badgeTitle: String {
        switch self {
        case .hiRes: "Hi-Res"
        case .lossless: "无损"
        case .high: "320K"
        case .standard: "128K"
        }
    }
}

extension Track {
    var highestKnownQuality: Quality {
        TrackQualityOption.available(for: self).first?.quality ?? .standard
    }
}

struct QualityBadge: View {
    let quality: Quality

    @Environment(\.m3Scheme) private var scheme

    var body: some View {
        Text(quality.badgeTitle)
            .font(.system(size: 8.75, weight: .semibold))
            .tracking(0.08)
            .foregroundStyle(foreground)
            .padding(.horizontal, 5)
            .frame(minWidth: 27, minHeight: 16)
            .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .fixedSize()
    }

    private var background: Color {
        switch quality {
        case .hiRes: scheme.tertiaryContainer
        case .lossless: scheme.secondaryContainer
        case .high, .standard: scheme.surfaceContainerHighest
        }
    }

    private var foreground: Color {
        switch quality {
        case .hiRes: scheme.onTertiaryContainer
        case .lossless: scheme.onSecondaryContainer
        case .high, .standard: scheme.onSurfaceVariant
        }
    }
}
