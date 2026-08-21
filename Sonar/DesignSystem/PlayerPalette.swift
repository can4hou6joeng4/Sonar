import SwiftUI

struct PlayerPalette {
    struct HexValues: Equatable, Sendable {
        let surface: String
        let ink: String
        let muted: String
        let queueBackground: String
    }

    let hex: HexValues

    var surface: Color { Color(hex: hex.surface) ?? .clear }
    var ink: Color { Color(hex: hex.ink) ?? .clear }
    var muted: Color { Color(hex: hex.muted) ?? .clear }
    var queueBackground: Color { Color(hex: hex.queueBackground) ?? .clear }

    init(scheme: M3Scheme) {
        let surface = scheme.isDark ? scheme.hex.surfaceContainerLow : "#E2E2DF"
        let ink = scheme.isDark ? scheme.hex.onSurface : "#07111E"
        let muted = scheme.isDark ? scheme.hex.onSurfaceVariant : "#70757C"
        let queueBase = scheme.isDark ? "#000000" : "#FFFFFF"
        hex = HexValues(
            surface: surface,
            ink: ink,
            muted: muted,
            queueBackground: M3Scheme.mixHex(top: queueBase, bottom: surface, alpha: 0.32)
        )
    }
}

private struct PlayerPaletteEnvironmentKey: EnvironmentKey {
    static let defaultValue = PlayerPalette(
        scheme: .tonalSpot(seedHex: M3Scheme.fallbackSeedHex, dark: false)
    )
}

extension EnvironmentValues {
    var playerPalette: PlayerPalette {
        get { self[PlayerPaletteEnvironmentKey.self] }
        set { self[PlayerPaletteEnvironmentKey.self] = newValue }
    }
}
