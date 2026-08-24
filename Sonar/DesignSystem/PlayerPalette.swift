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
        hex = HexValues(
            surface: scheme.isDark ? "#3D392F" : "#575142",
            ink: "#FFFFFF",
            muted: "#B8B5AE",
            queueBackground: scheme.isDark ? "#24221D" : "#37342C"
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
