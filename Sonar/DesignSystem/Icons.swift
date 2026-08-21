import SwiftUI

enum ShellTab: Int, CaseIterable, Identifiable {
    case discover
    case songs
    case player
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .discover: "发现"
        case .songs: "歌曲"
        case .player: "播放"
        case .settings: "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .discover: "safari"
        case .songs: "music.note.list"
        case .player: "waveform"
        case .settings: "slider.horizontal.3"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .discover: "bottom-tab-discover"
        case .songs: "bottom-tab-songs"
        case .player: "bottom-tab-player"
        case .settings: "bottom-tab-settings"
        }
    }
}
