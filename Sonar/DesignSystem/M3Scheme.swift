import SwiftUI

enum NCMDesignTokens {
    struct Palette: Equatable, Sendable {
        let background: String
        let card: String
        let ink: String
        let secondaryInk: String
        let tertiaryInk: String
        let divider: String
        let accent: String

        static let light = Palette(
            background: "#F5F7FB", card: "#FFFFFF", ink: "#0C0C23",
            secondaryInk: "#838190", tertiaryInk: "#B6B6C0",
            divider: "#E8E8EE", accent: "#FF3738"
        )
        static let dark = Palette(
            background: "#0D0D11", card: "#1B1B1F", ink: "#F3F3F3",
            secondaryInk: "#858587", tertiaryInk: "#55555E",
            divider: "#232327", accent: "#FF3A39"
        )
    }

    enum Typography {
        static let sectionTitle: CGFloat = 18
        static let sectionAction: CGFloat = 12
        static let shortcut: CGFloat = 13
        static let playlistCardTitle: CGFloat = 13
        static let playCount: CGFloat = 10
        static let songTitle: CGFloat = 16
        static let songSubtitle: CGFloat = 12
        static let selectedTab: CGFloat = 17
        static let tab: CGFloat = 16
        static let miniPlayer: CGFloat = 15
        static let libraryTitle: CGFloat = 30
        static let playerTitle: CGFloat = 20
        static let playerArtist: CGFloat = 13
        static let timecode: CGFloat = 10.5
        static let activeLyric: CGFloat = 19
        static let lyric: CGFloat = 16
        static let lyricTranslation: CGFloat = 13
        static let queueTitle: CGFloat = 15
        static let queueSubtitle: CGFloat = 12
        static let qualityBadge: CGFloat = 9
    }

    enum Layout {
        static let horizontalPadding: CGFloat = 16
        static let navigationHeight: CGFloat = 44
        static let tabBarHeight: CGFloat = 50
        static let miniPlayerHeight: CGFloat = 56
        static let songRowHeight: CGFloat = 60
        static let minimumTouchTarget: CGFloat = 44
        static let bottomContentSpacing: CGFloat = 12
        static let miniPlayerHorizontalInset: CGFloat = 8
        static let miniPlayerBottomSpacing: CGFloat = 2
        static let miniArtworkSize: CGFloat = 44
        static let miniControlSize: CGFloat = 44
        static let shortcutHeight: CGFloat = 44
        static let shortcutCornerRadius: CGFloat = 10
        static let shortcutSpacing: CGFloat = 9
        static let playlistCardWidth: CGFloat = 112
        static let playlistArtworkCornerRadius: CGFloat = 8
        static let playlistRowHeight: CGFloat = 66
        static let playlistArtworkSize: CGFloat = 50
        static let queueRowHeight: CGFloat = 68
    }

    enum Player {
        static let topLightness = 0.35
        static let bottomLightness = 0.23
        static let saturation = 0.15
        static let fallbackHue = 40.0
        static let discWidthRatio: CGFloat = 0.753
        static let artworkRatio: CGFloat = 0.68
        static let tonearmSizeRatio: CGFloat = 0.538
        static let tonearmPivotRatio: CGFloat = 0.14
        static let tonearmTopRatio: CGFloat = -0.282
        static let discTopClearanceRatio: CGFloat = 0.36
        static let primaryInk = Color.white.opacity(0.96)
        static let secondaryInk = Color.white.opacity(0.62)
        static let tertiaryInk = Color.white.opacity(0.34)
        static let progressTrack = Color.white.opacity(0.24)
    }

    enum Layer {
        static let tabRoot = 0.0
        static let childPage = 5.0
        static let miniPlayer = 19.0
        static let tabBar = 20.0
        static let player = 30.0
        static let sheet = 40.0
        static let toast = 60.0
    }
}

// Compatibility layer for views that have not yet migrated to NCMDesignTokens.
// The former seed-driven Material palette is intentionally gone.
struct M3Scheme {
    static let fallbackSeedHex = NCMDesignTokens.Palette.light.accent

    struct HexValues: Equatable, Sendable {
        let primary: String
        let onPrimary: String
        let primaryContainer: String
        let onPrimaryContainer: String
        let secondary: String
        let secondaryContainer: String
        let onSecondaryContainer: String
        let tertiaryContainer: String
        let onTertiaryContainer: String
        let surface: String
        let surfaceContainerLowest: String
        let surfaceContainerLow: String
        let surfaceContainer: String
        let surfaceContainerHigh: String
        let surfaceContainerHighest: String
        let onSurface: String
        let onSurfaceVariant: String
        let outline: String
        let outlineVariant: String
        let error: String
        let onError: String
        let appSurface: String
        let appInputFill: String
        let capsuleBackground: String
    }

    let seedHex: String
    let isDark: Bool
    let hex: HexValues

    var primary: Color { color(hex.primary) }
    var onPrimary: Color { color(hex.onPrimary) }
    var primaryContainer: Color { color(hex.primaryContainer) }
    var onPrimaryContainer: Color { color(hex.onPrimaryContainer) }
    var secondary: Color { color(hex.secondary) }
    var secondaryContainer: Color { color(hex.secondaryContainer) }
    var onSecondaryContainer: Color { color(hex.onSecondaryContainer) }
    var tertiaryContainer: Color { color(hex.tertiaryContainer) }
    var onTertiaryContainer: Color { color(hex.onTertiaryContainer) }
    var surface: Color { color(hex.surface) }
    var surfaceContainerLowest: Color { color(hex.surfaceContainerLowest) }
    var surfaceContainerLow: Color { color(hex.surfaceContainerLow) }
    var surfaceContainer: Color { color(hex.surfaceContainer) }
    var surfaceContainerHigh: Color { color(hex.surfaceContainerHigh) }
    var surfaceContainerHighest: Color { color(hex.surfaceContainerHighest) }
    var onSurface: Color { color(hex.onSurface) }
    var onSurfaceVariant: Color { color(hex.onSurfaceVariant) }
    var outline: Color { color(hex.outline) }
    var outlineVariant: Color { color(hex.outlineVariant) }
    var error: Color { color(hex.error) }
    var onError: Color { color(hex.onError) }
    var appSurface: Color { color(hex.appSurface) }
    var appInputFill: Color { color(hex.appInputFill) }
    var capsuleBackground: Color { color(hex.capsuleBackground) }

    static func tonalSpot(seedHex _: String, dark: Bool) -> M3Scheme {
        let palette = dark ? NCMDesignTokens.Palette.dark : .light
        let primaryContainer = dark ? "#5A1F20" : "#FFE3E3"
        let elevatedCard = dark ? "#202025" : "#F0F1F5"
        let values = HexValues(
            primary: palette.accent,
            onPrimary: "#FFFFFF",
            primaryContainer: primaryContainer,
            onPrimaryContainer: dark ? "#FFFFFF" : palette.ink,
            secondary: palette.accent,
            secondaryContainer: primaryContainer,
            onSecondaryContainer: dark ? "#FFFFFF" : palette.ink,
            tertiaryContainer: primaryContainer,
            onTertiaryContainer: dark ? "#FFFFFF" : palette.ink,
            surface: palette.background,
            surfaceContainerLowest: palette.background,
            surfaceContainerLow: palette.card,
            surfaceContainer: palette.card,
            surfaceContainerHigh: elevatedCard,
            surfaceContainerHighest: elevatedCard,
            onSurface: palette.ink,
            onSurfaceVariant: palette.secondaryInk,
            outline: palette.tertiaryInk,
            outlineVariant: palette.divider,
            error: palette.accent,
            onError: "#FFFFFF",
            appSurface: palette.background,
            appInputFill: palette.card,
            capsuleBackground: palette.card
        )
        return M3Scheme(seedHex: palette.accent, isDark: dark, hex: values)
    }

    static func normalizedHex(_ value: String) -> String? {
        var digits = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6, UInt64(digits, radix: 16) != nil else { return nil }
        return "#\(digits.uppercased())"
    }

    static func mixHex(top: String, bottom: String, alpha: Double) -> String {
        let topRGB = rgb(from: top)
        let bottomRGB = rgb(from: bottom)
        return hex(from: (
            red: topRGB.red * alpha + bottomRGB.red * (1 - alpha),
            green: topRGB.green * alpha + bottomRGB.green * (1 - alpha),
            blue: topRGB.blue * alpha + bottomRGB.blue * (1 - alpha)
        ))
    }

    private func color(_ value: String) -> Color {
        Color(hex: value) ?? .clear
    }

    private static func rgb(from hex: String) -> (red: Double, green: Double, blue: Double) {
        let digits = normalizedHex(hex)?.dropFirst() ?? "000000"
        let value = UInt64(digits, radix: 16) ?? 0
        return (
            Double((value >> 16) & 0xFF),
            Double((value >> 8) & 0xFF),
            Double(value & 0xFF)
        )
    }

    private static func hex(from rgb: (red: Double, green: Double, blue: Double)) -> String {
        let components = [rgb.red, rgb.green, rgb.blue].map {
            min(max(Int($0.rounded()), 0), 255)
        }
        return String(format: "#%02X%02X%02X", components[0], components[1], components[2])
    }
}

extension Color {
    init?(hex: String) {
        guard let normalized = M3Scheme.normalizedHex(hex),
              let number = UInt64(normalized.dropFirst(), radix: 16) else { return nil }
        self.init(
            .sRGB,
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255,
            opacity: 1
        )
    }
}

private struct M3SchemeEnvironmentKey: EnvironmentKey {
    static let defaultValue = M3Scheme.tonalSpot(seedHex: M3Scheme.fallbackSeedHex, dark: false)
}

extension EnvironmentValues {
    var m3Scheme: M3Scheme {
        get { self[M3SchemeEnvironmentKey.self] }
        set { self[M3SchemeEnvironmentKey.self] = newValue }
    }
}
