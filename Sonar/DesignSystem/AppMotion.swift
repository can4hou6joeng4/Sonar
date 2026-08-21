import SwiftUI

enum AppMotion {
    static let short: TimeInterval = 0.18
    static let medium: TimeInterval = 0.30
    static let long: TimeInterval = 0.50

    static func emphasized(duration: TimeInterval = medium, reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return .timingCurve(0.2, 0, 0, 1, duration: duration)
    }

    static func emphasizedDecelerate(duration: TimeInterval = medium, reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return .timingCurve(0.05, 0.7, 0.1, 1, duration: duration)
    }

    static func emphasizedAccelerate(duration: TimeInterval = medium, reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return .timingCurve(0.3, 0, 0.8, 0.15, duration: duration)
    }

    static func standardSpring(reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return .interpolatingSpring(mass: 1, stiffness: 540, damping: 36)
    }

    static func expressiveSpring(reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return .interpolatingSpring(mass: 1, stiffness: 420, damping: 24)
    }
}
