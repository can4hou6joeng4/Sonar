import SwiftUI
import UIKit

private struct ArtworkServiceKey: EnvironmentKey {
    static let defaultValue: ArtworkService? = nil
}

extension EnvironmentValues {
    var artworkService: ArtworkService? {
        get { self[ArtworkServiceKey.self] }
        set { self[ArtworkServiceKey.self] = newValue }
    }
}

struct PlayerArtwork: View {
    let track: Track?
    let size: CGFloat
    var circular = false
    var cornerRadius: CGFloat = 10

    @Environment(\.artworkService) private var artworkService
    @Environment(\.m3Scheme) private var scheme
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(circular ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
        .task(id: track?.musicID) {
            image = nil
            guard let track, let artworkService else { return }
            image = try? await artworkService.image(for: track)
        }
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Rectangle()
            .fill(scheme.surfaceContainerHighest)
            .overlay {
                Image(systemName: "music.note")
                    .font(.system(size: size > 100 ? 52 : 19, weight: .medium))
                    .foregroundStyle(scheme.primary)
            }
    }
}

// 兼容列表和底部胶囊的既有调用点，播放器主体统一使用 PlayerArtwork。
struct ArtworkThumbnail: View {
    let track: Track?
    let size: CGFloat

    var body: some View {
        PlayerArtwork(track: track, size: size)
    }
}
