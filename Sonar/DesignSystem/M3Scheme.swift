import SwiftUI

struct M3Scheme {
    static let fallbackSeedHex = "#2196F3"

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

    static func tonalSpot(seedHex: String, dark: Bool) -> M3Scheme {
        let normalizedSeed = normalizedHex(seedHex) ?? Self.fallbackSeedHex
        let hue = ColorMath.lch(from: normalizedSeed).hue
        let primary = { ColorMath.tone(hue: hue, chroma: 36, tone: $0) }
        let secondary = { ColorMath.tone(hue: hue, chroma: 16, tone: $0) }
        let tertiary = { ColorMath.tone(hue: (hue + 60).truncatingRemainder(dividingBy: 360), chroma: 24, tone: $0) }
        let neutral = { ColorMath.tone(hue: hue, chroma: 6, tone: $0) }
        let neutralVariant = { ColorMath.tone(hue: hue, chroma: 8, tone: $0) }

        let values: HexValues
        if dark {
            let appSurface = neutral(10)
            let containerHigh = neutral(17)
            let primaryValue = primary(80)
            values = HexValues(
                primary: primaryValue,
                onPrimary: primary(20),
                primaryContainer: primary(30),
                onPrimaryContainer: primary(90),
                secondary: secondary(80),
                secondaryContainer: secondary(30),
                onSecondaryContainer: secondary(90),
                tertiaryContainer: tertiary(30),
                onTertiaryContainer: tertiary(90),
                surface: neutral(6),
                surfaceContainerLowest: neutral(4),
                surfaceContainerLow: appSurface,
                surfaceContainer: neutral(12),
                surfaceContainerHigh: containerHigh,
                surfaceContainerHighest: neutral(22),
                onSurface: neutral(90),
                onSurfaceVariant: neutralVariant(80),
                outline: neutralVariant(60),
                outlineVariant: neutralVariant(30),
                error: "#FFB4AB",
                onError: "#690005",
                appSurface: appSurface,
                appInputFill: ColorMath.mix(top: primaryValue, bottom: appSurface, alpha: 0.14),
                capsuleBackground: ColorMath.mix(
                    top: primaryValue,
                    bottom: ColorMath.mix(top: containerHigh, bottom: appSurface, alpha: 0.90),
                    alpha: 0.04
                )
            )
        } else {
            let appSurface = neutral(96)
            let containerHigh = neutral(92)
            let primaryValue = primary(40)
            values = HexValues(
                primary: primaryValue,
                onPrimary: primary(100),
                primaryContainer: primary(90),
                onPrimaryContainer: primary(10),
                secondary: secondary(40),
                secondaryContainer: secondary(90),
                onSecondaryContainer: secondary(10),
                tertiaryContainer: tertiary(90),
                onTertiaryContainer: tertiary(10),
                surface: neutral(98),
                surfaceContainerLowest: neutral(100),
                surfaceContainerLow: appSurface,
                surfaceContainer: neutral(94),
                surfaceContainerHigh: containerHigh,
                surfaceContainerHighest: neutral(90),
                onSurface: neutral(10),
                onSurfaceVariant: neutralVariant(30),
                outline: neutralVariant(50),
                outlineVariant: neutralVariant(80),
                error: "#BA1A1A",
                onError: "#FFFFFF",
                appSurface: appSurface,
                appInputFill: ColorMath.mix(top: primaryValue, bottom: appSurface, alpha: 0.07),
                capsuleBackground: ColorMath.mix(
                    top: primaryValue,
                    bottom: ColorMath.mix(top: containerHigh, bottom: appSurface, alpha: 0.90),
                    alpha: 0.025
                )
            )
        }
        return M3Scheme(seedHex: normalizedSeed, isDark: dark, hex: values)
    }

    static func normalizedHex(_ value: String) -> String? {
        var digits = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        if digits.count == 3 { digits = digits.map { "\($0)\($0)" }.joined() }
        guard digits.count == 6, UInt64(digits, radix: 16) != nil else { return nil }
        return "#\(digits.uppercased())"
    }

    static func mixHex(top: String, bottom: String, alpha: Double) -> String {
        ColorMath.mix(top: top, bottom: bottom, alpha: alpha)
    }

    private func color(_ value: String) -> Color {
        Color(hex: value) ?? .clear
    }
}

private enum ColorMath {
    private static let whitePoint = (x: 0.95047, y: 1.0, z: 1.08883)

    struct LCh {
        let lightness: Double
        let chroma: Double
        let hue: Double
    }

    static func lch(from hex: String) -> LCh {
        let xyz = rgbToXYZ(rgb(from: hex))
        let lab = xyzToLab(xyz)
        var hue = atan2(lab.b, lab.a) * 180 / .pi
        if hue < 0 { hue += 360 }
        return LCh(lightness: lab.lightness, chroma: hypot(lab.a, lab.b), hue: hue)
    }

    static func tone(hue: Double, chroma: Double, tone: Double) -> String {
        let radians = hue * .pi / 180
        let full = labToRGB(lightness: tone, a: chroma * cos(radians), b: chroma * sin(radians))
        if inGamut(full) { return hex(from: full) }

        var low = 0.0
        var high = chroma
        for _ in 0..<18 {
            let candidate = (low + high) / 2
            let rgb = labToRGB(
                lightness: tone,
                a: candidate * cos(radians),
                b: candidate * sin(radians)
            )
            if inGamut(rgb) { low = candidate } else { high = candidate }
        }
        return hex(from: labToRGB(lightness: tone, a: low * cos(radians), b: low * sin(radians)))
    }

    static func mix(top: String, bottom: String, alpha: Double) -> String {
        let topRGB = rgb(from: top)
        let bottomRGB = rgb(from: bottom)
        return hex(from: (
            red: topRGB.red * alpha + bottomRGB.red * (1 - alpha),
            green: topRGB.green * alpha + bottomRGB.green * (1 - alpha),
            blue: topRGB.blue * alpha + bottomRGB.blue * (1 - alpha)
        ))
    }

    private static func rgb(from hex: String) -> (red: Double, green: Double, blue: Double) {
        let digits = M3Scheme.normalizedHex(hex)?.dropFirst() ?? "000000"
        let value = UInt64(digits, radix: 16) ?? 0
        return (
            Double((value >> 16) & 0xFF),
            Double((value >> 8) & 0xFF),
            Double(value & 0xFF)
        )
    }

    private static func rgbToXYZ(_ rgb: (red: Double, green: Double, blue: Double)) -> (x: Double, y: Double, z: Double) {
        let red = linearize(rgb.red)
        let green = linearize(rgb.green)
        let blue = linearize(rgb.blue)
        return (
            0.4124564 * red + 0.3575761 * green + 0.1804375 * blue,
            0.2126729 * red + 0.7151522 * green + 0.0721750 * blue,
            0.0193339 * red + 0.1191920 * green + 0.9503041 * blue
        )
    }

    private static func xyzToLab(_ xyz: (x: Double, y: Double, z: Double)) -> (lightness: Double, a: Double, b: Double) {
        let fx = labForward(xyz.x / whitePoint.x)
        let fy = labForward(xyz.y / whitePoint.y)
        let fz = labForward(xyz.z / whitePoint.z)
        return (116 * fy - 16, 500 * (fx - fy), 200 * (fy - fz))
    }

    private static func labToRGB(lightness: Double, a: Double, b: Double) -> (red: Double, green: Double, blue: Double) {
        let fy = (lightness + 16) / 116
        let fx = fy + a / 500
        let fz = fy - b / 200
        let x = whitePoint.x * labInverse(fx)
        let y = whitePoint.y * labInverse(fy)
        let z = whitePoint.z * labInverse(fz)
        return (
            delinearize(3.2404542 * x - 1.5371385 * y - 0.4985314 * z),
            delinearize(-0.9692660 * x + 1.8760108 * y + 0.0415560 * z),
            delinearize(0.0556434 * x - 0.2040259 * y + 1.0572252 * z)
        )
    }

    private static func linearize(_ component: Double) -> Double {
        let value = component / 255
        return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    private static func delinearize(_ component: Double) -> Double {
        255 * (component <= 0.0031308 ? 12.92 * component : 1.055 * pow(component, 1 / 2.4) - 0.055)
    }

    private static func labForward(_ value: Double) -> Double {
        value > 0.008856452 ? pow(value, 1 / 3) : 7.787037 * value + 16 / 116
    }

    private static func labInverse(_ value: Double) -> Double {
        let cube = value * value * value
        return cube > 0.008856452 ? cube : (value - 16 / 116) / 7.787037
    }

    private static func inGamut(_ rgb: (red: Double, green: Double, blue: Double)) -> Bool {
        (-0.6...255.6).contains(rgb.red)
            && (-0.6...255.6).contains(rgb.green)
            && (-0.6...255.6).contains(rgb.blue)
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
