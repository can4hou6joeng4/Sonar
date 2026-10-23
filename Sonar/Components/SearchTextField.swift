import SwiftUI
import UIKit

/// 搜索输入框（UIKit 承载）。
///
/// 用 SwiftUI `TextField` 时，拼音/日文等**组合输入**的中间态（marked text）会被
/// `onChange` 当成正式文本，导致每敲一个字母就触发一次搜索、组合串被重置，
/// 表现为「选不了输入法 / 拼不出拼音」。这里直接监听 `UITextField.markedTextRange`：
/// 组合期间只同步文本、不触发搜索；组合结束后再回调一次。
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
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.smartQuotesType = .no
        field.smartDashesType = .no
        field.smartInsertDeleteType = .no
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

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.parent = self
        uiView.textColor = textColor
        uiView.placeholder = placeholder
        // 组合输入期间不要回写文本，否则会打断候选词。
        if uiView.markedTextRange == nil, uiView.text != text {
            uiView.text = text
        }
        if isFocused, !uiView.isFirstResponder {
            DispatchQueue.main.async {
                guard !uiView.isFirstResponder else { return }
                uiView.becomeFirstResponder()
            }
        } else if !isFocused, uiView.isFirstResponder {
            DispatchQueue.main.async {
                guard uiView.isFirstResponder else { return }
                uiView.resignFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SearchTextField

        init(_ parent: SearchTextField) {
            self.parent = parent
        }

        @objc func editingChanged(_ field: UITextField) {
            let value = field.text ?? ""
            if parent.text != value { parent.text = value }
            guard field.markedTextRange == nil else { return }
            parent.onCommitText(value)
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            if !parent.isFocused { parent.isFocused = true }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            if parent.isFocused { parent.isFocused = false }
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }
    }
}
