import Observation
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system = "跟随系统"
    case light = "明亮"
    case dark = "深色"

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "跟随系统"
        // 保留旧 rawValue 读取已有偏好，只把界面文案对齐当前原型。
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    func resolved(using systemColorScheme: ColorScheme) -> ColorScheme {
        colorScheme ?? systemColorScheme
    }
}

enum ThemeSeedPreset: String, CaseIterable, Identifiable, Sendable {
    case blue
    case purple
    case green
    case orange
    case pink
    case teal
    case red
    case indigo
    case amber
    case cyan

    var id: Self { self }
    var name: String {
        switch self {
        case .blue: "蓝色"
        case .purple: "紫色"
        case .green: "绿色"
        case .orange: "橙色"
        case .pink: "粉色"
        case .teal: "青绿色"
        case .red: "红色"
        case .indigo: "靛蓝"
        case .amber: "琥珀"
        case .cyan: "青色"
        }
    }

    var hex: String {
        switch self {
        case .blue: "#2196F3"
        case .purple: "#9C27B0"
        case .green: "#4CAF50"
        case .orange: "#FF9800"
        case .pink: "#E91E63"
        case .teal: "#009688"
        case .red: "#F44336"
        case .indigo: "#3F51B5"
        case .amber: "#FFC107"
        case .cyan: "#00BCD4"
        }
    }
}

enum ThemeSeedSource: String, CaseIterable, Identifiable, Sendable {
    case artwork
    case preset
    case fallback

    var id: Self { self }
}

@MainActor
@Observable
final class SonarThemeState {
    static let fallbackHex = M3Scheme.fallbackSeedHex

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private static let appearanceKey = "appearanceMode"
    @ObservationIgnored private static let seedSourceKey = "themeSeedSource"
    @ObservationIgnored private static let seedPresetKey = "themeSeedPreset"

    var appearanceMode: AppearanceMode {
        didSet { defaults.set(appearanceMode.rawValue, forKey: Self.appearanceKey) }
    }

    var seedSource: ThemeSeedSource {
        didSet { defaults.set(seedSource.rawValue, forKey: Self.seedSourceKey) }
    }

    var selectedPreset: ThemeSeedPreset {
        didSet { defaults.set(selectedPreset.rawValue, forKey: Self.seedPresetKey) }
    }

    private(set) var artworkSeedHex: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        appearanceMode = defaults.string(forKey: Self.appearanceKey)
            .flatMap(AppearanceMode.init(rawValue:)) ?? .system
        seedSource = defaults.string(forKey: Self.seedSourceKey)
            .flatMap(ThemeSeedSource.init(rawValue:)) ?? .artwork
        selectedPreset = defaults.string(forKey: Self.seedPresetKey)
            .flatMap(ThemeSeedPreset.init(rawValue:)) ?? .blue
    }

    var resolvedSeedHex: String {
        switch seedSource {
        case .artwork:
            artworkSeedHex ?? Self.fallbackHex
        case .preset:
            selectedPreset.hex
        case .fallback:
            Self.fallbackHex
        }
    }

    var accent: Color {
        Color(hex: NCMDesignTokens.Palette.light.accent) ?? .red
    }

    var ambient: [Color] {
        ArtworkPalette.from(accentHex: resolvedSeedHex).ambientHex.compactMap(Color.init(hex:))
    }

    func scheme(for systemColorScheme: ColorScheme) -> M3Scheme {
        let resolved = appearanceMode.resolved(using: systemColorScheme)
        return .tonalSpot(seedHex: Self.fallbackHex, dark: resolved == .dark)
    }

    func update(accentHex: String?) {
        artworkSeedHex = accentHex.flatMap(M3Scheme.normalizedHex)
    }

    func useArtworkSeed() {
        seedSource = .artwork
    }

    func usePreset(_ preset: ThemeSeedPreset) {
        selectedPreset = preset
        seedSource = .preset
    }

    func useFallbackSeed() {
        seedSource = .fallback
    }
}
