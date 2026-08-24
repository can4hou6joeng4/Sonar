import Observation
import QuartzCore
import SwiftUI

enum PlayerPullMetrics {
    static let dismissVelocity: CGFloat = 550
    static let dismissDistance: CGFloat = 140
    static let upwardResistance: CGFloat = 0.28
    static let maximumUpwardTravel: CGFloat = 46
    static let feedbackDistance: CGFloat = 560

    static func shouldDismiss(translationY: CGFloat, velocityY: CGFloat) -> Bool {
        translationY > 0 && (velocityY > dismissVelocity || translationY > dismissDistance)
    }

    static func resistedTranslation(_ translationY: CGFloat) -> CGFloat {
        guard translationY < 0 else { return translationY }
        return max(translationY * upwardResistance, -maximumUpwardTravel)
    }

    static func feedback(for translationY: CGFloat) -> (scale: CGFloat, opacity: Double) {
        let progress = min(max(translationY / feedbackDistance, 0), 1)
        return (
            scale: 1 - progress * 0.05,
            opacity: Double(1 - progress * 0.28)
        )
    }
}

enum EdgeBackMetrics {
    static let activationWidth: CGFloat = 26
    static let dismissVelocity: CGFloat = 500
    static let dismissDistanceRatio: CGFloat = 0.32
    static let backgroundParallaxRatio: CGFloat = 0.22

    static func canStart(at x: CGFloat) -> Bool {
        x < activationWidth
    }

    static func shouldDismiss(translationX: CGFloat, velocityX: CGFloat, containerWidth: CGFloat) -> Bool {
        translationX > 0
            && (velocityX > dismissVelocity || translationX > containerWidth * dismissDistanceRatio)
    }
}

@MainActor
@Observable
final class PlayerPullController {
    private(set) var pull = 0.0
    private(set) var playerMounted = false
    private(set) var translationY: CGFloat = 0
    @ObservationIgnored private var pendingOpenTask: Task<Void, Never>?

    var toolbarReveal: Double { min(max(1 - pull, 0), 1) }
    var scale: CGFloat { PlayerPullMetrics.feedback(for: translationY).scale }
    var opacity: Double { PlayerPullMetrics.feedback(for: translationY).opacity }

    func warm() {
        playerMounted = true
    }

    func beginDismissInteraction() {
        pendingOpenTask?.cancel()
        pendingOpenTask = nil
        warm()
    }

    func updateDismiss(translationY: CGFloat) {
        self.translationY = PlayerPullMetrics.resistedTranslation(translationY)
    }

    func endDismissInteraction(velocityY: CGFloat, reduceMotion: Bool) {
        if PlayerPullMetrics.shouldDismiss(translationY: translationY, velocityY: velocityY) {
            close(reduceMotion: reduceMotion)
        } else {
            resetTranslation(reduceMotion: reduceMotion)
        }
    }

    func open(reduceMotion: Bool) {
        warm()
        pendingOpenTask?.cancel()
        guard !reduceMotion else {
            setPresented(true, disablesAnimations: true)
            return
        }
        pendingOpenTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            pendingOpenTask = nil
            withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: AppMotion.long)) {
                self.pull = 1
                self.translationY = 0
            }
        }
    }

    func close(reduceMotion: Bool) {
        pendingOpenTask?.cancel()
        pendingOpenTask = nil
        guard !reduceMotion else {
            setPresented(false, disablesAnimations: true)
            return
        }
        withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: AppMotion.long)) {
            pull = 0
            translationY = 0
        }
    }

    private func resetTranslation(reduceMotion: Bool) {
        guard !reduceMotion else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { translationY = 0 }
            return
        }
        withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: AppMotion.long)) {
            translationY = 0
        }
    }

    private func setPresented(_ presented: Bool, disablesAnimations: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = disablesAnimations
        withTransaction(transaction) {
            pull = presented ? 1 : 0
            translationY = 0
        }
    }
}

private struct PlayerDismissGestureModifier: ViewModifier {
    @Environment(\.sonarReduceMotion) private var reduceMotion

    let controller: PlayerPullController

    @State private var lastTranslationY: CGFloat?
    @State private var lastTimestamp: CFTimeInterval?
    @State private var velocityY: CGFloat = 0

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 5, coordinateSpace: .global)
                .onChanged(handleChanged)
                .onEnded(handleEnded)
        )
    }

    private func handleChanged(_ value: DragGesture.Value) {
        let now = CACurrentMediaTime()
        if lastTranslationY == nil {
            controller.beginDismissInteraction()
            lastTranslationY = 0
            lastTimestamp = now
        }
        let previous = lastTranslationY ?? 0
        let delta = value.translation.height - previous
        if let lastTimestamp {
            let interval = now - lastTimestamp
            if interval > 0 { velocityY = delta / interval }
        }
        lastTranslationY = value.translation.height
        lastTimestamp = now
        controller.updateDismiss(translationY: value.translation.height)
    }

    private func handleEnded(_ value: DragGesture.Value) {
        let finalDelta = value.translation.height - (lastTranslationY ?? value.translation.height)
        if abs(finalDelta) > 0.01, let lastTimestamp {
            let interval = CACurrentMediaTime() - lastTimestamp
            if interval > 0 { velocityY = finalDelta / interval }
        }
        controller.endDismissInteraction(velocityY: velocityY, reduceMotion: reduceMotion)
        lastTranslationY = nil
        lastTimestamp = nil
        velocityY = 0
    }
}

extension View {
    func playerDismissGesture(controller: PlayerPullController) -> some View {
        modifier(PlayerDismissGestureModifier(controller: controller))
    }

    func ncmEdgeSwipeBack() -> some View {
        modifier(EdgeSwipeBackModifier())
    }
}

private struct EdgeSwipeBackModifier: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.sonarReduceMotion) private var reduceMotion

    @State private var isActive = false
    @State private var translationX: CGFloat = 0
    @State private var lastTranslationX: CGFloat = 0
    @State private var lastTimestamp: CFTimeInterval?
    @State private var velocityX: CGFloat = 0

    func body(content: Content) -> some View {
        GeometryReader { proxy in
            content
                .frame(width: proxy.size.width, height: proxy.size.height)
                .offset(x: translationX)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 5, coordinateSpace: .global)
                        .onChanged { value in handleChanged(value) }
                        .onEnded { value in handleEnded(value, width: proxy.size.width) }
                )
        }
    }

    private func handleChanged(_ value: DragGesture.Value) {
        guard isActive || EdgeBackMetrics.canStart(at: value.startLocation.x) else { return }
        let now = CACurrentMediaTime()
        if !isActive {
            isActive = true
            lastTranslationX = 0
            lastTimestamp = now
        }
        let current = max(value.translation.width, 0)
        let delta = current - lastTranslationX
        if let lastTimestamp {
            let interval = now - lastTimestamp
            if interval > 0 { velocityX = delta / interval }
        }
        translationX = current
        lastTranslationX = current
        lastTimestamp = now
    }

    private func handleEnded(_ value: DragGesture.Value, width: CGFloat) {
        guard isActive else { return }
        let shouldDismiss = EdgeBackMetrics.shouldDismiss(
            translationX: max(value.translation.width, translationX),
            velocityX: velocityX,
            containerWidth: width
        )
        if shouldDismiss {
            dismiss()
        } else if reduceMotion {
            translationX = 0
        } else {
            withAnimation(.timingCurve(0.32, 0.72, 0, 1, duration: AppMotion.medium)) {
                translationX = 0
            }
        }
        isActive = false
        lastTranslationX = 0
        lastTimestamp = nil
        velocityX = 0
    }
}
