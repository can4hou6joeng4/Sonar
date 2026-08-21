import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct FlowingLightBackground: View {
    let track: Track?

    @Environment(\.artworkService) private var artworkService
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.playerPalette) private var palette
    @Environment(\.sonarReduceMotion) private var reduceMotion
    @State private var currentImage: CGImage?
    @State private var previousImage: CGImage?
    @State private var currentKey = ""

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                palette.surface
                if let previousImage {
                    backgroundImage(previousImage)
                }
                if let currentImage {
                    backgroundImage(currentImage)
                        .transition(.opacity)
                }
            }
            .task(id: renderKey(size: proxy.size)) {
                await update(size: proxy.size)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func backgroundImage(_ image: CGImage) -> some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.low)
            .scaledToFill()
            .ignoresSafeArea()
    }

    private func renderKey(size: CGSize) -> String {
        "\(track?.musicID ?? "empty")@\(Int(size.width))x\(Int(size.height))@\(colorScheme == .dark ? "d" : "l")"
    }

    @MainActor
    private func update(size: CGSize) async {
        let key = renderKey(size: size)
        guard key != currentKey else { return }
        currentKey = key
        guard let track, let artworkService,
              let artwork = try? await artworkService.image(for: track),
              let source = artwork.cgImage else {
            previousImage = nil
            currentImage = nil
            return
        }

        let rendered = await FlowingLightRenderer.shared.render(
            source: source,
            key: key,
            size: size,
            displayScale: UIScreen.main.scale,
            dark: colorScheme == .dark
        )
        guard currentKey == key, let rendered else { return }
        previousImage = currentImage
        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { currentImage = rendered }
        } else {
            withAnimation(AppMotion.emphasized(duration: AppMotion.long, reduceMotion: false)) {
                currentImage = rendered
            }
        }
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 1 : 520))
        guard currentKey == key else { return }
        previousImage = nil
    }
}

private actor FlowingLightRenderer {
    static let shared = FlowingLightRenderer()

    private let context = CIContext(options: [.cacheIntermediates: true])
    private var cache: [String: CGImage] = [:]
    private var order: [String] = []

    func render(
        source: CGImage,
        key: String,
        size: CGSize,
        displayScale: CGFloat,
        dark: Bool
    ) -> CGImage? {
        if let cached = cache[key] { return cached }
        guard size.width > 0, size.height > 0 else { return nil }

        let compositionScale: CGFloat = displayScale * 160 >= 420 ? 32 : 20
        let physicalWidth = size.width * displayScale
        let physicalHeight = size.height * displayScale
        let visibleWidth = physicalWidth / compositionScale
        let visibleHeight = physicalHeight / compositionScale
        let canvasWidth = ceil(visibleWidth) + 58
        let canvasHeight = ceil(visibleHeight) + 58
        let canvasRect = CGRect(x: 0, y: 0, width: canvasWidth, height: canvasHeight)

        let sourceImage = CIImage(cgImage: source)
        let sourceExtent = sourceImage.extent
        let average = averageColor(source: source)
        let base = CIImage(color: CIColor(cgColor: average)).cropped(to: canvasRect)

        let saturated = sourceImage.applyingFilter(
            "CIColorControls",
            parameters: [kCIInputSaturationKey: 2.5]
        )
        let side = max(canvasWidth, canvasHeight) * 1.3
        let left = -(side - canvasWidth) / 2
        let top = -(side - canvasHeight) / 2
        let placements = [
            CGPoint(x: left, y: top),
            CGPoint(x: left - canvasWidth * 0.95, y: top - canvasHeight * 0.7),
            CGPoint(x: left - canvasWidth * 0.5, y: top + canvasHeight * 0.7),
        ]

        var layer = base
        for placement in placements {
            let scaleX = side / sourceExtent.width
            let scaleY = side / sourceExtent.height
            let image = saturated
                .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
                .transformed(by: CGAffineTransform(translationX: placement.x, y: placement.y))
            layer = image.composited(over: layer)
        }

        var composition = layer
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: 25])
            .cropped(to: canvasRect)

        let scrimColor = dark ? CIColor(red: 0, green: 0, blue: 0, alpha: 0.322) : CIColor(red: 1, green: 1, blue: 1, alpha: 0.584)
        let secondScrimColor = dark ? CIColor(red: 0, green: 0, blue: 0, alpha: 0.102) : CIColor(red: 1, green: 1, blue: 1, alpha: 0.165)
        composition = CIImage(color: scrimColor).cropped(to: canvasRect).composited(over: composition)
        composition = CIImage(color: secondScrimColor).cropped(to: canvasRect).composited(over: composition)

        let crop = CGRect(
            x: max(0, (canvasWidth - visibleWidth) / 2),
            y: max(0, (canvasHeight - visibleHeight) / 2),
            width: visibleWidth,
            height: visibleHeight
        )
        let outputWidth = max(1, ceil(physicalWidth / 4))
        let outputHeight = max(1, ceil(physicalHeight / 4))
        let output = composition
            .cropped(to: crop)
            .transformed(by: CGAffineTransform(
                scaleX: outputWidth / crop.width,
                y: outputHeight / crop.height
            ))
            .transformed(by: CGAffineTransform(translationX: -crop.minX * outputWidth / crop.width, y: -crop.minY * outputHeight / crop.height))
        let outputRect = CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight)
        guard let result = context.createCGImage(output, from: outputRect) else { return nil }

        cache[key] = result
        order.append(key)
        if order.count > 12 {
            cache[order.removeFirst()] = nil
        }
        return result
    }

    private func averageColor(source: CGImage) -> CGColor {
        let width = 24
        let height = 24
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return UIColor.darkGray.cgColor }
        context.interpolationQuality = .medium
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var count = 0.0
        for row in 0..<5 {
            let y = min(height - 1, Int((Double(row) + 0.5) * Double(height) / 5))
            for column in 0..<5 {
                let x = min(width - 1, Int((Double(column) + 0.5) * Double(width) / 5))
                let offset = (y * width + x) * 4
                red += Double(pixels[offset]) / 255
                green += Double(pixels[offset + 1]) / 255
                blue += Double(pixels[offset + 2]) / 255
                count += 1
            }
        }
        return CGColor(red: red / count, green: green / count, blue: blue / count, alpha: 1)
    }
}
