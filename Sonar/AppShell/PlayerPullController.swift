import Observation
import QuartzCore
import SwiftUI

enum PlayerPullMetrics {
    static let flingVelocity: CGFloat = 400
    static let revealThreshold = 0.28
    static let hideThreshold = 0.72
    static let toolbarFadeProgress = 0.15

    static func settleDuration(remaining: Double) -> TimeInterval {
        (140 + 180 * min(max(remaining, 0), 1)) / 1_000
    }

    static func settleTarget(
        pull: Double,
        velocityY: CGFloat,
        lastDeltaY: CGFloat
    ) -> Double {
        if abs(velocityY) > flingVelocity {
            return velocityY < 0 ? 1 : 0
        }
        if lastDeltaY < 0 {
            return pull >= revealThreshold ? 1 : 0
        }
        if lastDeltaY > 0 {
            return pull > hideThreshold ? 1 : 0
        }
        return pull >= 0.5 ? 1 : 0
    }
}

@MainActor
@Observable
final class PlayerPullController {
    private(set) var pull = 0.0
    private(set) var playerMounted = false
    private var interactionStartPull = 0.0
    @ObservationIgnored private var pendingOpenTask: Task<Void, Never>?

    var toolbarReveal: Double {
        min(max(1 - pull / PlayerPullMetrics.toolbarFadeProgress, 0), 1)
    }

    func warm() {
        // 播放层一旦预热就常驻，避免反复触发后续流光背景的冷启动。
        playerMounted = true
    }

    func beginInteraction() {
        pendingOpenTask?.cancel()
        pendingOpenTask = nil
        warm()
        interactionStartPull = pull
    }

    func update(translationY: CGFloat, viewportHeight: CGFloat) {
        guard viewportHeight > 0 else { return }
        pull = min(max(interactionStartPull - Double(translationY / viewportHeight), 0), 1)
    }

    func endInteraction(
        velocityY: CGFloat,
        lastDeltaY: CGFloat,
        reduceMotion: Bool
    ) {
        let target = PlayerPullMetrics.settleTarget(
            pull: pull,
            velocityY: velocityY,
            lastDeltaY: lastDeltaY
        )
        settle(to: target, reduceMotion: reduceMotion)
    }

    func cancelInteraction(reduceMotion: Bool) {
        settle(to: interactionStartPull >= 0.5 ? 1 : 0, reduceMotion: reduceMotion)
    }

    func open(reduceMotion: Bool) {
        warm()
        pendingOpenTask?.cancel()
        guard !reduceMotion else {
            settle(to: 1, reduceMotion: true)
            return
        }

        // 首次点击会在同一轮事件里挂载图层并提交位移动画；先让离屏图层完成一次布局，
        // 否则 SwiftUI 可能只保留初始 transform，最终 pull 已到 1 但画面仍停在 Shell。
        pendingOpenTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self else { return }
            pendingOpenTask = nil
            settle(to: 1, reduceMotion: false)
        }
    }

    func close(reduceMotion: Bool) {
        pendingOpenTask?.cancel()
        pendingOpenTask = nil
        settle(to: 0, reduceMotion: reduceMotion)
    }

    private func settle(to target: Double, reduceMotion: Bool) {
        let remaining = abs(pull - target)
        guard !reduceMotion, remaining >= 0.001 else {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { pull = target }
            return
        }

        let duration = PlayerPullMetrics.settleDuration(remaining: remaining)
        let animation = target > pull
            ? AppMotion.emphasizedDecelerate(duration: duration, reduceMotion: false)
            : AppMotion.emphasizedAccelerate(duration: duration, reduceMotion: false)
        withAnimation(animation) { pull = target }
    }
}

private struct PlayerPullHandleModifier: ViewModifier {
    @Environment(\.sonarReduceMotion) private var reduceMotion

    let controller: PlayerPullController
    let viewportHeight: CGFloat

    @State private var lastTranslationY: CGFloat?
    @State private var lastTimestamp: CFTimeInterval?
    @State private var lastDeltaY: CGFloat = 0
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
            controller.beginInteraction()
            lastTranslationY = 0
            lastTimestamp = now
        }

        let previousTranslation = lastTranslationY ?? 0
        let delta = value.translation.height - previousTranslation
        if let lastTimestamp {
            let interval = now - lastTimestamp
            if interval > 0 {
                velocityY = delta / interval
            }
        }
        lastDeltaY = delta
        self.lastTranslationY = value.translation.height
        lastTimestamp = now
        controller.update(translationY: value.translation.height, viewportHeight: viewportHeight)
    }

    private func handleEnded(_ value: DragGesture.Value) {
        if let lastTranslationY {
            let finalDelta = value.translation.height - lastTranslationY
            if abs(finalDelta) > 0.01 {
                lastDeltaY = finalDelta
            }
        }
        controller.endInteraction(
            velocityY: velocityY,
            lastDeltaY: lastDeltaY,
            reduceMotion: reduceMotion
        )
        resetSamples()
    }

    private func resetSamples() {
        lastTranslationY = nil
        lastTimestamp = nil
        lastDeltaY = 0
        velocityY = 0
    }
}

extension View {
    func playerPullHandle(
        controller: PlayerPullController,
        viewportHeight: CGFloat
    ) -> some View {
        modifier(PlayerPullHandleModifier(controller: controller, viewportHeight: viewportHeight))
    }
}
