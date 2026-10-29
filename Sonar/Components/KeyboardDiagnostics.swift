import Foundation
import os
import UIKit

/// 第三方输入法（微信输入法等）在首次呼出键盘时可能连不上键盘宿主，
/// 表现为键盘可见但按键无响应，切到其他应用再回来才恢复。
///
/// 这里集中记录键盘生命周期与输入事件，并提供搜索框的兼容策略。
/// 事件只写入系统日志（Console / `log stream`），不保留内存副本。
@MainActor
final class KeyboardDiagnostics {
    /// 键盘弹出后的兼容处理方式。设置入口已移除，当前固定使用 `.refocus`
    /// （等价于切后台再回来）；其余两项保留用于临时排查。
    enum RepairMode {
        /// 不处理，仅记录事件。
        case off
        /// 调用 `reloadInputViews()` 重建输入视图。
        case reload
        /// 取消并重新获取焦点。
        case refocus
    }

    static let shared = KeyboardDiagnostics()

    private static let logger = Logger(subsystem: "cn.bobochang.sonar", category: "keyboard")

    static var currentRepairMode: RepairMode { .refocus }

    private var isObserving = false
    private var observers: [NSObjectProtocol] = []

    func start() {
        guard !isObserving else { return }
        isObserving = true
        observe(UIResponder.keyboardWillShowNotification) { [weak self] _ in
            self?.log("kbd_will_show")
        }
        observe(UIResponder.keyboardDidShowNotification) { [weak self] notification in
            guard let self else { return }
            self.log("kbd_did_show \(self.keyboardSummary(notification))")
        }
        observe(UIResponder.keyboardWillHideNotification) { [weak self] _ in
            self?.log("kbd_will_hide")
        }
        observe(UITextInputMode.currentInputModeDidChangeNotification) { [weak self] _ in
            self?.log("input_mode_changed \(self?.inputModeSummary() ?? "")")
        }
        observe(UIApplication.didBecomeActiveNotification) { [weak self] _ in
            self?.log("app_active")
        }
        observe(UIApplication.willResignActiveNotification) { [weak self] _ in
            self?.log("app_inactive")
        }
    }

    func log(_ event: String) {
        Self.logger.info("keyboard \(event, privacy: .public)")
    }

    /// 系统里已启用的输入模式列表。第三方键盘只能通过 KVC 读取标识，仅用于诊断。
    func inputModeSummary() -> String {
        let active = UITextInputMode.activeInputModes.map(Self.describe)
        return "active=[\(active.joined(separator: " | "))]"
    }

    func summary(for field: UITextField?) -> String {
        "cur=\(Self.describe(field?.textInputMode))"
    }

    private func keyboardSummary(_ notification: Notification) -> String {
        let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        let height = frame.map { Int($0.height) } ?? 0
        return "h=\(height) \(inputModeSummary())"
    }

    static func describe(_ mode: UITextInputMode?) -> String {
        guard let mode else { return "nil" }
        let language = mode.primaryLanguage ?? "?"
        if mode.responds(to: NSSelectorFromString("identifier")),
           let identifier = mode.value(forKey: "identifier") as? String {
            return "\(identifier)(\(language))"
        }
        return language
    }

    private func observe(_ name: Notification.Name, handler: @escaping @MainActor (Notification) -> Void) {
        let token = NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { notification in
            MainActor.assumeIsolated {
                handler(notification)
            }
        }
        observers.append(token)
    }
}
