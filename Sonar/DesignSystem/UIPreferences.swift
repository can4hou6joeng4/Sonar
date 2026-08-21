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
    private static let qualityKey = "preferredPlaybackQuality"

    var miniLyricsEnabled: Bool {
        didSet { defaults.set(miniLyricsEnabled, forKey: Self.miniLyricsKey) }
    }

    var motionEnabled: Bool {
        didSet { defaults.set(motionEnabled, forKey: Self.motionKey) }
    }

    var preferredQuality: Quality {
        didSet { defaults.set(preferredQuality.rawValue, forKey: Self.qualityKey) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        miniLyricsEnabled = defaults.object(forKey: Self.miniLyricsKey) as? Bool ?? true
        motionEnabled = defaults.object(forKey: Self.motionKey) as? Bool ?? true
        preferredQuality = defaults.string(forKey: Self.qualityKey)
            .flatMap(Quality.init(rawValue:)) ?? .hiRes
    }
}
