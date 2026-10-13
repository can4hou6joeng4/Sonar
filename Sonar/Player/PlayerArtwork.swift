import SwiftUI
import UIKit

/// Owns the commit boundary for view-scoped artwork and its derived metadata.
/// A new generation also rejects A -> B -> A completions for the first A.
@MainActor
final class ArtworkRequestGate {
    struct Request: Equatable {
        fileprivate let generation = UUID()
        let trackID: String?
    }

    private var latest: Request?

    func begin(trackID: String?) -> Request {
        let request = Request(trackID: trackID)
        latest = request
        return request
    }

    @discardableResult
    func commit(_ request: Request, currentTrackID: String?, updates: () -> Void) -> Bool {
        guard !Task.isCancelled, latest == request, request.trackID == currentTrackID else { return false }
        updates()
        return true
    }
}

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
    var animatesChanges = false

    @Environment(\.artworkService) private var artworkService
    @Environment(\.m3Scheme) private var scheme
    @Environment(\.sonarReduceMotion) private var reduceMotion
    @State private var image: UIImage?
    @State private var displayedTrackID: String?
    @State private var artworkRequests = ArtworkRequestGate()

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .id(displayedTrackID)
                    .transition(.opacity)
            } else {
                placeholder
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .clipShape(circular ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
        .task(id: track?.musicID) {
            guard !Task.isCancelled else { return }
            let request = artworkRequests.begin(trackID: track?.musicID)
            guard let track, let artworkService else {
                image = nil
                displayedTrackID = nil
                return
            }
            let loadedImage = try? await artworkService.image(for: track)
            artworkRequests.commit(request, currentTrackID: track.musicID) {
                withAnimation(animatesChanges ? AppMotion.emphasized(duration: 0.4, reduceMotion: reduceMotion) : nil) {
                    image = loadedImage
                    displayedTrackID = track.musicID
                }
            }
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
