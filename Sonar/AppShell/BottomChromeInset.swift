import SwiftUI

/// 底部常驻控件（迷你条 + 底栏）会盖住滚动内容。
/// `safeAreaInset` 加在 NavigationStack 上时不会作用到 push 进去的页面，
/// 所以由 shell 注入高度，各页自己挂 `.bottomChromeInset()`。
enum BottomChromeLayout {
    /// 底栏 50 + 底部留白 6 + 视觉缓冲 10；有迷你条时再加 62 + 8。
    static func height(hasCurrentTrack: Bool) -> CGFloat {
        let tabBar: CGFloat = 50 + 6 + 10
        guard hasCurrentTrack else { return tabBar }
        return tabBar + 62 + 8
    }
}

private struct BottomChromeHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var bottomChromeHeight: CGFloat {
        get { self[BottomChromeHeightKey.self] }
        set { self[BottomChromeHeightKey.self] = newValue }
    }
}

private struct BottomChromeInsetModifier: ViewModifier {
    @Environment(\.bottomChromeHeight) private var height

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: max(height, 0))
                .accessibilityHidden(true)
        }
    }
}

extension View {
    /// 让滚动内容能滚到迷你条/底栏上方。
    func bottomChromeInset() -> some View {
        modifier(BottomChromeInsetModifier())
    }
}
