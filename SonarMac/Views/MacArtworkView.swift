import AppKit
import SwiftUI

/// Both cached track art and catalog images use the same quiet placeholder.
struct MacArtworkView: View {
    var track: Track? = nil
    var url: String? = nil
    var service: ArtworkService? = nil
    var size: CGFloat = 48
    var radius: CGFloat = 10
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius).fill(.quaternary)
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else if let url, let remoteURL = URL(string: url) {
                AsyncImage(url: remoteURL) { result in
                    if let image = result.image { image.resizable().scaledToFill() }
                    else { placeholder }
                }
            } else { placeholder }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .accessibilityHidden(true)
        .task(id: track?.musicID) {
            image = nil
            guard let track, let service else { return }
            let result = try? await service.image(for: track)
            guard !Task.isCancelled else { return }
            image = result
        }
    }

    private var placeholder: some View {
        Image(systemName: "waveform")
            .font(.system(size: max(14, size * 0.28), weight: .medium))
            .foregroundStyle(.secondary)
    }
}

struct MacEmptyState: View {
    let title: String
    let description: String
    var symbol: String = "music.note"

    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(description))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MacInlineError: View {
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
            Text(message).font(.callout).textSelection(.enabled)
            Spacer(minLength: 8)
            if let retry { Button("重试", action: retry) }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

func macTime(_ value: TimeInterval) -> String {
    let seconds = value.isFinite ? max(0, Int(value)) : 0
    return String(format: "%d:%02d", seconds / 60, seconds % 60)
}

extension Quality {
    var macTitle: String {
        switch self {
        case .standard: "标准 · 128 kbps"
        case .high: "高品质 · 320 kbps"
        case .lossless: "无损 · FLAC"
        case .hiRes: "高解析度 · Hi-Res"
        }
    }
}
