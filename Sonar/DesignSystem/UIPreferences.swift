import Foundation
import Observation
import SwiftUI

private struct SonarReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var sonarReduceMotion: Bool {
        get { self[SonarReduceMotionKey.self] }
        set { self[SonarReduceMotionKey.self] = newValue }
    }
}

@MainActor
@Observable
final class UIPlaybackPreferences {
    @ObservationIgnored private let defaults: UserDefaults

    private static let miniLyricsKey = "miniLyricsEnabled"
    private static let motionKey = "appMotionEnabled"
    private static let coverAccentKey = "coverAccentEnabled"

    var miniLyricsEnabled: Bool {
        didSet { defaults.set(miniLyricsEnabled, forKey: Self.miniLyricsKey) }
    }

    var motionEnabled: Bool {
        didSet { defaults.set(motionEnabled, forKey: Self.motionKey) }
    }

    var coverAccentEnabled: Bool {
        didSet { defaults.set(coverAccentEnabled, forKey: Self.coverAccentKey) }
    }

    // 音质偏好归 PlaybackService：只有它能拿这个值去重新解析播放地址，
    // 放在这里会变成一份没人执行的副本。

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        miniLyricsEnabled = defaults.object(forKey: Self.miniLyricsKey) as? Bool ?? true
        motionEnabled = defaults.object(forKey: Self.motionKey) as? Bool ?? true
        coverAccentEnabled = defaults.object(forKey: Self.coverAccentKey) as? Bool ?? true
    }
}
