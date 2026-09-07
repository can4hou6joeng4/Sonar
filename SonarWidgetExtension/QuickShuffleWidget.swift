import WidgetKit
import SwiftUI

struct QuickShuffleEntry: TimelineEntry {
    let date: Date
    let favoritesCount: Int
}

struct QuickShuffleTimelineProvider: TimelineProvider {
    typealias Entry = QuickShuffleEntry

    func placeholder(in context: Context) -> QuickShuffleEntry {
        QuickShuffleEntry(date: Date(), favoritesCount: 130)
    }

    func getSnapshot(in context: Context, completion: @escaping (QuickShuffleEntry) -> Void) {
        let snapshot = WidgetShareStore.shared.loadSnapshot()
        completion(QuickShuffleEntry(date: Date(), favoritesCount: snapshot.favoritesCount))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickShuffleEntry>) -> Void) {
        let snapshot = WidgetShareStore.shared.loadSnapshot()
        let entry = QuickShuffleEntry(date: Date(), favoritesCount: snapshot.favoritesCount)
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct QuickShuffleWidgetView: View {
    let entry: QuickShuffleEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.2))
                        .frame(width: 34, height: 34)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.red)
                }

                Spacer()

                Image(systemName: "music.note.list")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 2) {
                Text("我喜欢的音乐")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)

                Text("\(entry.favoritesCount) 首精选收藏")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "shuffle")
                        .font(.system(size: 11, weight: .bold))
                    Text("随心听")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(Color.red)
                        .shadow(color: Color.red.opacity(0.4), radius: 6, x: 0, y: 3)
                )
                Spacer()
            }
            .padding(.top, 2)
        }
        .widgetURL(URL(string: "sonar://play-favorites?shuffle=true"))
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color(red: 0.24, green: 0.08, blue: 0.10),
                    Color(red: 0.10, green: 0.10, blue: 0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

struct QuickShuffleWidget: Widget {
    let kind: String = "QuickShuffleWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuickShuffleTimelineProvider()) { entry in
            QuickShuffleWidgetView(entry: entry)
        }
        .configurationDisplayName("我喜欢的音乐 · 随心听")
        .description("一键在桌面开启收藏歌曲的随机播放。")
        .supportedFamilies([.systemSmall])
    }
}
