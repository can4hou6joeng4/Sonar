import CoreGraphics
import Foundation

#if os(macOS)
import AppKit
public typealias PlatformImage = NSImage
#else
import UIKit
public typealias PlatformImage = UIImage
#endif

/// The artwork pipeline uses native image representations on each platform.
extension PlatformImage {
    var sonarCGImage: CGImage? {
        #if os(macOS)
        cgImage(forProposedRect: nil, context: nil, hints: nil)
        #else
        cgImage
        #endif
    }

    static func sonarImage(cgImage: CGImage) -> PlatformImage {
        #if os(macOS)
        NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        #else
        UIImage(cgImage: cgImage)
        #endif
    }

    func sonarJPEGData(compressionQuality: CGFloat) -> Data? {
        #if os(macOS)
        guard let image = sonarCGImage else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(
            using: .jpeg, properties: [.compressionFactor: compressionQuality]
        )
        #else
        jpegData(compressionQuality: compressionQuality)
        #endif
    }
}
