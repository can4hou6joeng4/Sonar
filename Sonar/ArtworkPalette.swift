import CoreGraphics
import Foundation
import UIKit

public struct ArtworkPalette: Equatable, Sendable {
    public let accentHex: String
    public let tintHex: String
    public let ambientHex: [String]
    public let glowHex: String

    public init(accentHex: String, tintHex: String, ambientHex: [String], glowHex: String) {
        self.accentHex = accentHex
        self.tintHex = tintHex
        self.ambientHex = ambientHex
        self.glowHex = glowHex
    }

    public static func from(accentHex: String) -> ArtworkPalette {
        let hsl = HSL(hex: accentHex) ?? HSL(h: 190, s: 72, l: 64)
        let accent = HSL(h: hsl.h, s: min(88, max(30, hsl.s)), l: min(74, max(56, hsl.l)))
        return ArtworkPalette(
            accentHex: accent.hex,
            tintHex: accent.hex,
            ambientHex: [
                HSL(h: accent.h, s: min(64, accent.s * 0.88), l: 21).hex,
                HSL(h: (accent.h + 28).truncatingRemainder(dividingBy: 360), s: min(54, accent.s * 0.68), l: 15).hex,
                HSL(h: (accent.h + 336).truncatingRemainder(dividingBy: 360), s: min(46, accent.s * 0.54), l: 11).hex,
            ],
            glowHex: accent.hex
        )
    }

    public static func accentHex(from image: UIImage) -> String? {
        guard let cgImage = image.cgImage else { return nil }
        let width = 44
        let height = 44
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                | CGBitmapInfo.byteOrder32Big.rawValue
        ) else { return nil }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        struct Bucket { var weight = 0.0; var h = 0.0; var s = 0.0; var l = 0.0 }
        var buckets = Array(repeating: Bucket(), count: 24)
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha >= 200 / 255 else { continue }
            let rgb = (Double(pixels[index]) / 255, Double(pixels[index + 1]) / 255, Double(pixels[index + 2]) / 255)
            let hsl = HSL(rgb: rgb)
            guard hsl.l >= 12, hsl.l <= 92, hsl.s >= 14 else { continue }
            let weight = hsl.s * (1 - abs(hsl.l - 55) / 70)
            guard weight > 0 else { continue }
            let bucket = min(23, Int(hsl.h / 15))
            buckets[bucket].weight += weight
            buckets[bucket].h += hsl.h * weight
            buckets[bucket].s += hsl.s * weight
            buckets[bucket].l += hsl.l * weight
        }
        guard let best = buckets.max(by: { $0.weight < $1.weight }), best.weight > 0 else { return nil }
        let saturation = best.s / best.weight
        guard saturation >= 12 else { return nil }
        let hsl = HSL(
            h: (best.h / best.weight).truncatingRemainder(dividingBy: 360),
            s: min(88, max(32, saturation)),
            l: min(72, max(54, best.l / best.weight))
        )
        return hsl.hex
    }

    private struct HSL {
        let h: Double
        let s: Double
        let l: Double

        init(h: Double, s: Double, l: Double) { self.h = h; self.s = s; self.l = l }

        init(rgb: (Double, Double, Double)) {
            let maxValue = max(rgb.0, rgb.1, rgb.2)
            let minValue = min(rgb.0, rgb.1, rgb.2)
            let delta = maxValue - minValue
            let lightness = (maxValue + minValue) * 50
            let saturation = delta == 0 ? 0 : delta / (1 - abs(2 * lightness / 100 - 1)) * 100
            let hue: Double
            if delta == 0 { hue = 0 }
            else if maxValue == rgb.0 { hue = 60 * (((rgb.1 - rgb.2) / delta).truncatingRemainder(dividingBy: 6)) }
            else if maxValue == rgb.1 { hue = 60 * (((rgb.2 - rgb.0) / delta) + 2) }
            else { hue = 60 * (((rgb.0 - rgb.1) / delta) + 4) }
            self.init(h: hue >= 0 ? hue : hue + 360, s: saturation, l: lightness)
        }

        init?(hex: String) {
            let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            guard value.count == 6 else { return nil }
            let components = stride(from: 0, to: 6, by: 2).compactMap { UInt8(value.dropFirst($0).prefix(2), radix: 16) }
            guard components.count == 3 else { return nil }
            let rgb = components
            self.init(rgb: (Double(rgb[0]) / 255, Double(rgb[1]) / 255, Double(rgb[2]) / 255))
        }

        var hex: String {
            let chroma = (1 - abs(2 * l / 100 - 1)) * s / 100
            let x = chroma * (1 - abs((h / 60).truncatingRemainder(dividingBy: 2) - 1))
            let m = l / 100 - chroma / 2
            let rgb: (Double, Double, Double)
            switch h {
            case 0..<60: rgb = (chroma, x, 0)
            case 60..<120: rgb = (x, chroma, 0)
            case 120..<180: rgb = (0, chroma, x)
            case 180..<240: rgb = (0, x, chroma)
            case 240..<300: rgb = (x, 0, chroma)
            default: rgb = (chroma, 0, x)
            }
            return String(format: "#%02X%02X%02X", Int(round((rgb.0 + m) * 255)), Int(round((rgb.1 + m) * 255)), Int(round((rgb.2 + m) * 255)))
        }
    }
}
