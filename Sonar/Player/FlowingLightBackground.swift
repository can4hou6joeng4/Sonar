import SwiftUI

struct FlowingLightBackground: View {
    let track: Track?

    @Environment(\.artworkService) private var artworkService
    @Environment(UIPlaybackPreferences.self) private var preferences
    @Environment(\.sonarReduceMotion) private var reduceMotion
    @State private var hue = NCMDesignTokens.Player.fallbackHue

    var body: some View {
        LinearGradient(
            colors: [
                Color(
                    hue: hue / 360,
                    saturation: preferences.coverAccentEnabled ? 0.48 : 0.18,
                    brightness: 0.46
                ),
                Color(
                    hue: hue / 360,
                    saturation: preferences.coverAccentEnabled ? 0.40 : 0.14,
                    brightness: 0.17
                ),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
        .animation(
            AppMotion.emphasized(duration: AppMotion.long, reduceMotion: reduceMotion),
            value: hue
        )
        .task(id: taskID) {
            let resolved = await resolvedHue()
            guard !Task.isCancelled else { return }
            hue = resolved
        }
        .accessibilityHidden(true)
    }

    private var taskID: String {
        "\(track?.musicID ?? "none")-\(preferences.coverAccentEnabled)"
    }

    private func resolvedHue() async -> Double {
        guard preferences.coverAccentEnabled,
              let track,
              let artworkService,
              let image = try? await artworkService.image(for: track),
              let accentHex = ArtworkPalette.accentHex(from: image),
              let rgb = Self.rgb(from: accentHex) else {
            return NCMDesignTokens.Player.fallbackHue
        }
        return Self.hue(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    private static func rgb(from hex: String) -> (red: CGFloat, green: CGFloat, blue: CGFloat)? {
        guard let normalized = M3Scheme.normalizedHex(hex),
              let value = UInt64(normalized.dropFirst(), radix: 16) else { return nil }
        return (
            CGFloat((value >> 16) & 0xFF) / 255,
            CGFloat((value >> 8) & 0xFF) / 255,
            CGFloat(value & 0xFF) / 255
        )
    }

    private static func hue(red: CGFloat, green: CGFloat, blue: CGFloat) -> Double {
        let maximum = max(red, green, blue)
        let minimum = min(red, green, blue)
        let delta = maximum - minimum
        guard delta > 0.0001 else { return NCMDesignTokens.Player.fallbackHue }

        let degrees: CGFloat
        if maximum == red {
            degrees = 60 * ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maximum == green {
            degrees = 60 * ((blue - red) / delta + 2)
        } else {
            degrees = 60 * ((red - green) / delta + 4)
        }
        return Double(degrees < 0 ? degrees + 360 : degrees)
    }
}
