import AppIntents
import WidgetKit

struct TogglePlayIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "播放 / 暂停"
    static var description = IntentDescription("切换当前歌曲的播放与暂停状态")

    func perform() async throws -> some IntentResult {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("cn.bobochang.sonar.remote.togglePlay" as CFString),
            nil,
            nil,
            true
        )
        var snapshot = WidgetShareStore.shared.loadSnapshot()
        if snapshot.hasTrack {
            snapshot = WidgetPlaybackSnapshot(
                title: snapshot.title,
                artist: snapshot.artist,
                album: snapshot.album,
                quality: snapshot.quality,
                isPlaying: !snapshot.isPlaying,
                hasTrack: snapshot.hasTrack,
                favoritesCount: snapshot.favoritesCount,
                updatedAt: Date()
            )
            WidgetShareStore.shared.saveSnapshot(snapshot, reloadWidgets: false)
        }
        return .result()
    }
}

struct NextTrackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "下一首"
    static var description = IntentDescription("播放下一首歌曲")

    func perform() async throws -> some IntentResult {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("cn.bobochang.sonar.remote.next" as CFString),
            nil,
            nil,
            true
        )
        return .result()
    }
}

struct PreviousTrackIntent: AudioPlaybackIntent {
    static var title: LocalizedStringResource = "上一首"
    static var description = IntentDescription("播放上一首歌曲")

    func perform() async throws -> some IntentResult {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("cn.bobochang.sonar.remote.previous" as CFString),
            nil,
            nil,
            true
        )
        return .result()
    }
}
