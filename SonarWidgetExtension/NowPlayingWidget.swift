import WidgetKit
import SwiftUI

struct NowPlayingEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetPlaybackSnapshot
    let artworkURL: URL?
}

struct NowPlayingTimelineProvider: TimelineProvider {
    typealias Entry = NowPlayingEntry

    func placeholder(in context: Context) -> NowPlayingEntry {
        NowPlayingEntry(date: Date(), snapshot: .empty, artworkURL: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (NowPlayingEntry) -> Void) {
        let snapshot = WidgetShareStore.shared.loadSnapshot()
        let artworkURL = WidgetShareStore.shared.artworkFileURL()
        completion(NowPlayingEntry(date: Date(), snapshot: snapshot, artworkURL: artworkURL))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NowPlayingEntry>) -> Void) {
        let snapshot = WidgetShareStore.shared.loadSnapshot()
        let artworkURL = WidgetShareStore.shared.artworkFileURL()
        let entry = NowPlayingEntry(date: Date(), snapshot: snapshot, artworkURL: artworkURL)
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct NowPlayingWidgetView: View {
    let entry: NowPlayingEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumView
            default:
                smallView
            }
        }
        .widgetURL(URL(string: "sonar://nowplaying"))
        .containerBackground(for: .widget) {
            backgroundView
        }
    }

    // MARK: - Subviews

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                artworkThumbnail(size: 52, cornerRadius: 10)
                Spacer()
                if entry.snapshot.isPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.red)
                        .symbolEffect(.variableColor.iterative.reversing, isActive: true)
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.snapshot.hasTrack ? entry.snapshot.title : "暂无播放")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(entry.snapshot.hasTrack ? entry.snapshot.artist : "轻点开启随心听")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if !entry.snapshot.quality.isEmpty {
                    qualityTag(entry.snapshot.quality)
                        .padding(.top, 2)
                }
            }
        }
    }

    private var mediumView: some View {
        HStack(spacing: 16) {
            artworkThumbnail(size: 106, cornerRadius: 14)

            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.snapshot.hasTrack ? entry.snapshot.title : "暂无播放")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if !entry.snapshot.quality.isEmpty {
                            qualityTag(entry.snapshot.quality)
                        }
                    }

                    Text(entry.snapshot.hasTrack ? entry.snapshot.artist : "轻点控制台或随心听开启音乐")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if entry.snapshot.hasTrack && !entry.snapshot.album.isEmpty {
                        Text(entry.snapshot.album)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Playback Control Buttons (iOS 17 AppIntents)
                HStack(spacing: 20) {
                    Button(intent: PreviousTrackIntent()) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)

                    Button(intent: TogglePlayIntent()) {
                        Image(systemName: entry.snapshot.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 44)
                            .background(Color.red, in: Circle())
                            .shadow(color: Color.red.opacity(0.4), radius: 6, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)

                    Button(intent: NextTrackIntent()) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 36, height: 36)
                            .background(Color.white.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func artworkThumbnail(size: CGFloat, cornerRadius: CGFloat) -> some View {
        ZStack {
            if let artworkURL = entry.artworkURL,
               let uiImage = UIImage(contentsOfFile: artworkURL.path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [Color(red: 0.22, green: 0.22, blue: 0.26), Color(red: 0.12, green: 0.12, blue: 0.15)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.36))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 3)
    }

    private func qualityTag(_ quality: String) -> some View {
        Text(quality)
            .font(.system(size: 9, weight: .heavy))
            .foregroundStyle(Color.red)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(Color.red.opacity(0.15))
            )
            .overlay(
                Capsule()
                    .stroke(Color.red.opacity(0.4), lineWidth: 0.5)
            )
    }

    private var backgroundView: some View {
        ZStack {
            if let artworkURL = entry.artworkURL,
               let uiImage = UIImage(contentsOfFile: artworkURL.path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 28)
                    .overlay(Color.black.opacity(0.68))
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.14, green: 0.14, blue: 0.17),
                        Color(red: 0.08, green: 0.08, blue: 0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }
}

struct NowPlayingWidget: Widget {
    let kind: String = "NowPlayingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NowPlayingTimelineProvider()) { entry in
            NowPlayingWidgetView(entry: entry)
        }
        .configurationDisplayName("正在播放")
        .description("展示当前播放歌曲、音质标识与桌面快捷控制。")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
