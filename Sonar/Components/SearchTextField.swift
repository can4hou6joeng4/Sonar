import SwiftUI
import UIKit

/// 搜索输入框（UIKit 承载）。
///
/// 用 SwiftUI `TextField` 时，拼音/日文等**组合输入**的中间态（marked text）会被
/// `onChange` 当成正式文本，导致每敲一个字母就触发一次搜索、组合串被重置，
/// 表现为「选不了输入法 / 拼不出拼音」。这里直接监听 `UITextField.markedTextRange`：
/// 组合期间只同步文本、不触发搜索；组合结束后再回调一次。
///
/// 等输入框挂在活跃窗口上再请求焦点，必要时重试；首次显示键盘后
/// 重新聚焦一次，以兼容需要重新连接宿主的第三方输入法。
struct SearchTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var placeholder: String
    var textColor: UIColor
    var onSubmit: () -> Void
    /// 组合输入结束、文本真正落定后调用。
    var onCommitText: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.placeholder = placeholder
        field.returnKeyType = .search
        // 使用标准输入特性；组合输入是否触发搜索由 markedTextRange 单独控制。
        field.autocorrectionType = .default
        field.autocapitalizationType = .sentences
        field.spellCheckingType = .default
        field.keyboardType = .default
        field.smartQuotesType = .default
        field.smartDashesType = .default
        field.smartInsertDeleteType = .default
        field.clearButtonMode = .never
        field.font = .systemFont(ofSize: 15)
        field.textColor = textColor
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )
        field.accessibilityIdentifier = "search-field"
        return field
    }

    static func dismantleUIView(_ uiView: UITextField, coordinator: Coordinator) {
        coordinator.cancelFocusRequest()
        coordinator.stopObservingKeyboard()
        uiView.delegate = nil
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        uiView.textColor = textColor
        uiView.placeholder = placeholder
        // 组合输入期间不要回写文本，否则会打断候选词。
        if uiView.markedTextRange == nil, uiView.text != text {
            uiView.text = text
        }
        if isFocused {
            context.coordinator.requestFocus(uiView)
        } else {
            context.coordinator.releaseFocus(uiView)
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SearchTextField
        private var focusWorkItem: DispatchWorkItem?
        private var keyboardObserver: NSObjectProtocol?
        private var didRepairForCurrentFocus = false
        private var isRepairingFocus = false
        private weak var currentField: UITextField?
        /// 约 2 秒（40 帧）足够覆盖浮层动画、旋转和首帧布局。
        private static let maxFocusAttempts = 40
        private static let initialFocusDelay: TimeInterval = 0.2
        private static let focusRetryInterval: TimeInterval = 0.05

        init(_ parent: SearchTextField) {
            self.parent = parent
        }

        /// 请求焦点：输入框还不在活跃窗口上时按帧重试，窗口稳定后才 `becomeFirstResponder`。
        func requestFocus(_ field: UITextField) {
            guard !field.isFirstResponder else {
                cancelFocusRequest()
                return
            }
            guard focusWorkItem == nil else { return }
            scheduleFocusRequest(field, attempt: 0)
        }

        /// 放弃焦点并取消尚未执行的重试。
        func releaseFocus(_ field: UITextField) {
            cancelFocusRequest()
            didRepairForCurrentFocus = false
            isRepairingFocus = false
            guard field.isFirstResponder else { return }
            DispatchQueue.main.async { [weak self, weak field] in
                guard let self, let field, !self.parent.isFocused, field.isFirstResponder else { return }
                field.resignFirstResponder()
            }
        }

        func cancelFocusRequest() {
            focusWorkItem?.cancel()
            focusWorkItem = nil
        }

        private func scheduleFocusRequest(_ field: UITextField, attempt: Int) {
            let delay = attempt == 0 ? Self.initialFocusDelay : Self.focusRetryInterval
            let workItem = DispatchWorkItem { [weak self, weak field] in
                guard let self, let field else { return }
                self.focusWorkItem = nil
                guard self.parent.isFocused, !field.isFirstResponder else { return }
                guard Self.isReadyForFocus(field) else {
                    KeyboardDiagnostics.shared.log("focus_not_ready a=\(attempt)")
                    if attempt < Self.maxFocusAttempts {
                        self.scheduleFocusRequest(field, attempt: attempt + 1)
                    } else {
                        KeyboardDiagnostics.shared.log("focus_timeout")
                    }
                    return
                }
                self.currentField = field
                self.installKeyboardObserver()
                let accepted = field.becomeFirstResponder()
                KeyboardDiagnostics.shared.log("become_first a=\(attempt) ok=\(accepted)")
                guard accepted else {
                    if attempt < Self.maxFocusAttempts {
                        self.scheduleFocusRequest(field, attempt: attempt + 1)
                    } else {
                        KeyboardDiagnostics.shared.log("focus_rejected")
                    }
                    return
                }
            }
            focusWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }

        /// 键盘首次显示后执行兼容处理，每次聚焦只执行一次。
        private func installKeyboardObserver() {
            guard keyboardObserver == nil else { return }
            keyboardObserver = NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardDidShowNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.repairKeyboardIfNeeded()
                }
            }
        }

        func stopObservingKeyboard() {
            if let keyboardObserver {
                NotificationCenter.default.removeObserver(keyboardObserver)
            }
            keyboardObserver = nil
        }

        private func repairKeyboardIfNeeded() {
            guard let field = currentField,
                  !didRepairForCurrentFocus,
                  parent.isFocused,
                  field.isFirstResponder else { return }
            let mode = KeyboardDiagnostics.currentRepairMode
            guard mode != .off else { return }
            didRepairForCurrentFocus = true
            switch mode {
            case .off:
                break
            case .reload:
                KeyboardDiagnostics.shared.log("repair_reload")
                field.reloadInputViews()
            case .refocus:
                KeyboardDiagnostics.shared.log("repair_refocus")
                isRepairingFocus = true
                field.resignFirstResponder()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self, weak field] in
                    guard let self, let field else { return }
                    guard self.parent.isFocused, !field.isFirstResponder else {
                        self.isRepairingFocus = false
                        return
                    }
                    let accepted = field.becomeFirstResponder()
                    self.isRepairingFocus = false
                    KeyboardDiagnostics.shared.log("repair_refocus_result ok=\(accepted)")
                }
            }
        }

        /// 只有真正挂在处于前台活跃状态的窗口上才适合要焦点。
        private static func isReadyForFocus(_ field: UITextField) -> Bool {
            guard !field.isHidden, field.alpha > 0, field.isUserInteractionEnabled else { return false }
            guard let window = field.window else { return false }
            guard let scene = window.windowScene, scene.activationState == .foregroundActive else { return false }
            return true
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            KeyboardDiagnostics.shared.log("should_change n=\(string.count)")
            return true
        }

        @objc func editingChanged(_ field: UITextField) {
            let value = field.text ?? ""
            KeyboardDiagnostics.shared.log("changed n=\(value.count)")
            if parent.text != value { parent.text = value }
            guard field.markedTextRange == nil else { return }
            parent.onCommitText(value)
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            cancelFocusRequest()
            currentField = textField
            installKeyboardObserver()
            KeyboardDiagnostics.shared.log("begin_edit \(KeyboardDiagnostics.shared.summary(for: textField))")
            if !parent.isFocused { parent.isFocused = true }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            guard !isRepairingFocus else {
                KeyboardDiagnostics.shared.log("end_edit_for_repair")
                return
            }
            didRepairForCurrentFocus = false
            KeyboardDiagnostics.shared.log("end_edit")
            if parent.isFocused { parent.isFocused = false }
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }
    }
}
