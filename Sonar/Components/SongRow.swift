import SwiftUI

struct SongRow: View {
    let track: Track
    var isCurrent = false
    var isSelected = false
    var isPlaying = false
    var onPlay: () -> Void
    var onAction: (() -> Void)?

    @Environment(\.m3Scheme) private var scheme

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onPlay) {
                HStack(spacing: 10) {
                    PlayerArtwork(track: track, size: 52)
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(scheme.outlineVariant.opacity(0.24), lineWidth: 1)
                        }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            if isCurrent {
                                PlayingEqualizer(isAnimating: isPlaying, color: primaryForeground)
                            }
                            Text(track.title)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(primaryForeground)
                                .lineLimit(1)
                        }
                        HStack(spacing: 6) {
                            QualityBadge(quality: track.highestKnownQuality)
                            Text([track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(secondaryForeground)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("song-row-play-\(track.musicID)")

            if let onAction {
                Button(action: onAction) {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(scheme.onSurfaceVariant)
                        .frame(width: 32, height: 32)
                        .background(scheme.surfaceContainerHighest, in: Circle())
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("加入歌单")
                .accessibilityIdentifier("song-row-add-to-playlist-\(track.musicID)")
            }
        }
        .padding(.leading, 4)
        .padding(.trailing, 2)
        .padding(.vertical, 8)
        .frame(minHeight: 68)
        .background(rowBackground)
        .contentShape(Rectangle())
    }

    private var rowBackground: Color {
        if isSelected { return scheme.primaryContainer.opacity(0.56) }
        if isCurrent { return scheme.primaryContainer.opacity(0.20) }
        return .clear
    }

    private var primaryForeground: Color {
        if isSelected { return scheme.onPrimaryContainer }
        if isCurrent { return scheme.primary }
        return scheme.onSurface
    }

    private var secondaryForeground: Color {
        if isSelected { return scheme.onPrimaryContainer.opacity(0.86) }
        if isCurrent { return scheme.primary.opacity(0.86) }
        return scheme.onSurfaceVariant
    }
}
