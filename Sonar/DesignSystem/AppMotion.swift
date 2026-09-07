import SwiftUI
import UIKit

enum AppHaptics {
    static func light() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.prepare()
        generator.impactOccurred()
    }

    static func medium() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
    }

    static func rigid() {
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.prepare()
        generator.impactOccurred()
    }

    static func selection() {
        let generator = UISelectionFeedbackGenerator()
        generator.prepare()
        generator.selectionChanged()
    }

    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
}

enum AppMotion {
    static let short: TimeInterval = 0.16
    static let medium: TimeInterval = 0.30
    static let long: TimeInterval = 0.42
    static let queueReorder: TimeInterval = 0.16
    static let tonearm: TimeInterval = 0.42
    static let discRotation: TimeInterval = 20
    static let lyricsFollowResume: TimeInterval = 3.5
    static let progressUpdate: TimeInterval = 0.2

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

struct BounceButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.94
    var opacity: CGFloat = 0.88
    var haptic: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .opacity(configuration.isPressed ? opacity : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.65), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed && haptic {
                    AppHaptics.light()
                }
            }
    }
}

struct CircleIconButtonStyle: ButtonStyle {
    var diameter: CGFloat = 36
    var haptic: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .opacity(configuration.isPressed ? 0.80 : 1.0)
            .background(
                Circle()
                    .fill(configuration.isPressed ? Color.white.opacity(0.14) : Color.clear)
                    .frame(width: diameter, height: diameter)
            )
            .animation(.spring(response: 0.24, dampingFraction: 0.62), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed && haptic {
                    AppHaptics.light()
                }
            }
    }
}

struct CellHighlightButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(configuration.isPressed ? Color.white.opacity(0.08) : Color.clear)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == BounceButtonStyle {
    static var bounce: BounceButtonStyle { BounceButtonStyle() }
    static func bounce(scale: CGFloat = 0.94, opacity: CGFloat = 0.88, haptic: Bool = true) -> BounceButtonStyle {
        BounceButtonStyle(scale: scale, opacity: opacity, haptic: haptic)
    }
}

extension ButtonStyle where Self == CircleIconButtonStyle {
    static var circleIcon: CircleIconButtonStyle { CircleIconButtonStyle() }
    static func circleIcon(diameter: CGFloat = 36, haptic: Bool = true) -> CircleIconButtonStyle {
        CircleIconButtonStyle(diameter: diameter, haptic: haptic)
    }
}

extension ButtonStyle where Self == CellHighlightButtonStyle {
    static var cellHighlight: CellHighlightButtonStyle { CellHighlightButtonStyle() }
}

