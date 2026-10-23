import SwiftUI
import UIKit

/// 歌词分享卡片：固定 330×440，用于 `ImageRenderer` 出图后走系统分享。
struct LyricsShareCard: View {
    let track: Track
    let artwork: UIImage?
    let lines: [String]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "#22222A") ?? .black, Color(hex: "#0B0B0E") ?? .black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    Group {
                        if let artwork {
                            Image(uiImage: artwork).resizable().scaledToFill()
                        } else {
                            Color.white.opacity(0.12)
                        }
                    }
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title)
                            .font(.system(size: 17, weight: .semibold))
                            .lineLimit(1)
                        Text(track.artist)
                            .font(.system(size: 12))
                            .opacity(0.65)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Text(line)
                            .font(.system(size: index == 0 ? 21 : 17, weight: index == 0 ? .bold : .medium))
                            .foregroundStyle(.white.opacity(index == 0 ? 1 : 0.72))
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                HStack {
                    Text("Sonar")
                        .font(.system(size: 12, weight: .semibold))
                        .opacity(0.55)
                    Spacer()
                    Text("music.163.com/song?id=\(track.songmid)")
                        .font(.system(size: 9))
                        .opacity(0.35)
                        .lineLimit(1)
                }
                .foregroundStyle(.white)
            }
            .padding(22)
        }
        .frame(width: 330, height: 440)
    }
}

@MainActor
enum LyricsShareCardRenderer {
    static func render(
        track: Track,
        artwork: UIImage?,
        lyrics: KaraokeLyrics,
        elapsed: TimeInterval
    ) -> UIImage? {
        let renderer = ImageRenderer(
            content: LyricsShareCard(
                track: track,
                artwork: artwork,
                lines: lines(lyrics: lyrics, elapsed: elapsed)
            )
        )
        renderer.scale = 3
        return renderer.uiImage
    }

    /// 取当前行 + 后续三行；没有歌词时退化为「正在听」文案。
    static func lines(lyrics: KaraokeLyrics, elapsed: TimeInterval) -> [String] {
        let all = lyrics.lines.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !all.isEmpty else { return ["正在听 \("" )"] }
        let ms = Int(elapsed * 1000)
        var index = all.firstIndex { $0.endMs >= ms } ?? 0
        index = min(max(0, index), max(0, all.count - 1))
        let slice = all[index...].prefix(4).map { $0.text }
        return Array(slice)
    }
}

/// 系统分享面板（UIImage）。
struct ActivityShareSheet: UIViewControllerRepresentable {
    let image: UIImage

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
