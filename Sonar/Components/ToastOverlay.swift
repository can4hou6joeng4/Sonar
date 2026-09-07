import Observation
import SwiftUI

@MainActor
@Observable
final class ToastCenter {
    private(set) var message: String?
    @ObservationIgnored private var dismissalTask: Task<Void, Never>?

    func show(_ message: String) {
        dismissalTask?.cancel()
        self.message = message
        dismissalTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1700))
            guard !Task.isCancelled else { return }
            self.message = nil
        }
    }
}

struct AppConfirmation: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let acknowledgment: String
}

@MainActor
@Observable
final class ConfirmationCenter {
    private(set) var confirmation: AppConfirmation?
    private var pendingConfirmation: AppConfirmation?

    func show(title: String, message: String, acknowledgment: String = "好") {
        confirmation = AppConfirmation(
            title: title,
            message: message,
            acknowledgment: acknowledgment
        )
    }

    func enqueueAfterPresentationDismissal(
        title: String,
        message: String,
        acknowledgment: String = "好"
    ) {
        pendingConfirmation = AppConfirmation(
            title: title,
            message: message,
            acknowledgment: acknowledgment
        )
    }

    func presentPendingAfterDismissal() async {
        guard let pendingConfirmation else { return }
        self.pendingConfirmation = nil
        await Task.yield()
        confirmation = pendingConfirmation
    }

    func acknowledge() {
        confirmation = nil
    }
}

struct ToastOverlay: View {
    @Environment(ToastCenter.self) private var toastCenter
    @Environment(\.m3Scheme) private var scheme
    @Environment(\.sonarReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let message = toastCenter.message {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(scheme.onSurface)
                    .padding(.horizontal, 18)
                    .frame(minHeight: 44)
                    .background(scheme.surfaceContainerHigh, in: Capsule())
                    .shadow(color: .black.opacity(0.18), radius: 12, y: 8)
                    .transition(.opacity.combined(with: .offset(y: 10)))
                    .accessibilityIdentifier("app-toast")
            }
        }
        .animation(
            AppMotion.emphasized(duration: AppMotion.short, reduceMotion: reduceMotion),
            value: toastCenter.message
        )
        .allowsHitTesting(false)
    }
}
