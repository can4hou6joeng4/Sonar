import SwiftUI

struct PlaylistDetailActions: View {
    @Environment(\.m3Scheme) private var scheme

    let isLoading: Bool
    let isFavoriteInProgress: Bool
    let isFavorite: Bool
    let showFavorite: Bool
    let onPlayAll: () -> Void
    let onFavorite: () -> Void

    var body: some View {
        PlaylistDetailActionsLayout {
            actionButton(
                title: isLoading ? "加载中" : "播放全部",
                systemImage: "play.fill",
                filled: true,
                isBusy: false,
                action: onPlayAll
            )
            .disabled(isLoading)
            .accessibilityIdentifier("playlist-play-all")

            if showFavorite {
                actionButton(
                    title: favoriteTitle,
                    systemImage: isFavorite ? "heart.fill" : "heart",
                    filled: false,
                    isBusy: isFavoriteInProgress,
                    action: onFavorite
                )
                .disabled(isLoading || isFavoriteInProgress)
                .accessibilityIdentifier("playlist-favorite")
            }
        }
        .frame(maxWidth: 900)
        .padding(.init(top: 4, leading: 16, bottom: 8, trailing: 16))
    }

    private var favoriteTitle: String {
        if isFavoriteInProgress { return isFavorite ? "取消中" : "收藏中" }
        return isFavorite ? "已收藏" : "收藏歌单"
    }

    private func actionButton(
        title: String,
        systemImage: String,
        filled: Bool,
        isBusy: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.body.weight(filled ? .semibold : .medium))
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(filled ? scheme.onPrimary : scheme.onSecondaryContainer)
            .background(filled ? scheme.primary : scheme.secondaryContainer)
        }
        .buttonStyle(.plain)
        .clipShape(Capsule())
    }
}

private struct PlaylistDetailActionsLayout: Layout {
    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? 340
        let compact = subviews.count > 1 && width < 340
        return CGSize(width: width, height: compact ? 106 : 48)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        guard let first = subviews.first else { return }
        guard subviews.count > 1 else {
            first.place(
                at: bounds.origin,
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: 48)
            )
            return
        }

        if bounds.width < 340 {
            first.place(
                at: bounds.origin,
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: 48)
            )
            subviews[1].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY + 58),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: 48)
            )
        } else {
            let available = bounds.width - 10
            let leadingWidth = available * 3 / 5
            first.place(
                at: bounds.origin,
                anchor: .topLeading,
                proposal: ProposedViewSize(width: leadingWidth, height: 48)
            )
            subviews[1].place(
                at: CGPoint(x: bounds.minX + leadingWidth + 10, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: available * 2 / 5, height: 48)
            )
        }
    }
}
