import Foundation
import Observation
import SwiftUI
import UIKit

/// 第三方输入法（微信输入法等）在首次呼出键盘时可能连不上键盘宿主，
/// 表现为键盘可见但按键无响应，切到其他应用再回来才恢复。
///
/// 记录键盘生命周期与输入事件，并提供搜索框的自动兼容策略。
@MainActor
@Observable
final class KeyboardDiagnostics {
    enum RepairMode: String, CaseIterable, Identifiable {
        case off
        case reload
        case refocus

        var id: String { rawValue }

        var title: String {
            switch self {
            case .off: "关闭"
            case .reload: "重建键盘"
            case .refocus: "重新聚焦"
            }
        }

        var subtitle: String {
            switch self {
            case .off: "不做处理，仅记录事件"
            case .reload: "键盘弹出后调用 reloadInputViews() 重建输入视图"
            case .refocus: "键盘弹出后取消并重新获取焦点（等同于切后台再回来）"
            }
        }
    }

    static let shared = KeyboardDiagnostics()

    static let repairModeKey = "sonar.keyboardRepair.mode"
    static let hudVisibleKey = "sonar.keyboardDiagnostics.hud"

    static var currentRepairMode: RepairMode {
        // 设置入口已移除，旧版本保存的关闭选项不再禁用兼容处理。
        .refocus
    }

    private(set) var lines: [String] = []
    private let startedAt = ProcessInfo.processInfo.systemUptime
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
        let ms = Int((ProcessInfo.processInfo.systemUptime - startedAt) * 1000)
        lines.append("\(ms) \(event)")
        if lines.count > 16 {
            lines.removeFirst(lines.count - 16)
        }
    }

    /// 当前键盘输入模式 + 系统里已启用的输入模式列表。
    /// 第三方键盘的标识只能通过 KVC 读取，仅用于诊断展示。
    func inputModeSummary() -> String {
        let active = UITextInputMode.activeInputModes.map(Self.describe)
        return "active=[\(active.joined(separator: " | "))]"
    }

    func summary(for field: UITextField?) -> String {
        let current = Self.describe(field?.textInputMode)
        return "cur=\(current)"
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

struct KeyboardDiagnosticsHUD: View {
    @State private var diagnostics = KeyboardDiagnostics.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(diagnostics.lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.black.opacity(0.78), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 12)
        .allowsHitTesting(false)
    }
}
