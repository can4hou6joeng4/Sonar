import SwiftUI

enum ShellTab: Int, CaseIterable, Identifiable {
    case home
    case library

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "首页"
        case .library: "我的"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .home: "bottom-tab-home"
        case .library: "bottom-tab-library"
        }
    }
}
