import Foundation
import Observation

/// 定时关闭：到点后执行传入动作（通常是暂停播放），界面可显示剩余时间。
@MainActor
@Observable
final class SleepTimer {
    private(set) var deadline: Date?
    private var task: Task<Void, Never>?

    var isActive: Bool { deadline != nil }

    var remainingText: String? {
        guard let deadline else { return nil }
        let remaining = max(0, Int(deadline.timeIntervalSinceNow.rounded()))
        let minutes = remaining / 60
        let seconds = remaining % 60
        return minutes > 0
            ? "剩 \(minutes) 分 \(String(format: "%02d", seconds)) 秒"
            : "剩 \(seconds) 秒"
    }

    func start(minutes: Int, action: @escaping @MainActor () -> Void) {
        cancel()
        deadline = Date().addingTimeInterval(TimeInterval(minutes * 60))
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, let deadline = self.deadline else { return }
                if Date() >= deadline {
                    self.deadline = nil
                    self.task = nil
                    action()
                    return
                }
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        deadline = nil
    }
}
