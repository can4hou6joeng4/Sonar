import SwiftUI

struct QualitySheet: View {
    let track: Track?

    @Environment(\.dismiss) private var dismiss
    @Environment(PlaybackService.self) private var playbackService
    @Environment(ToastCenter.self) private var toastCenter
    @Environment(\.m3Scheme) private var scheme

    private var options: [Quality: TrackQualityOption] {
        guard let track else { return [:] }
        return Dictionary(uniqueKeysWithValues: TrackQualityOption.available(for: track).map { ($0.quality, $0) })
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "播放音质")
                .accessibilityIdentifier("player-quality-sheet")
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(Quality.displayOrder, id: \.self) { quality in
                        let option = options[quality]
                        let isAvailable = track == nil || option != nil
                            Button {
                                apply(quality)
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(quality.title)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(scheme.onSurface)
                                        Text(option.map { $0.sizeText.isEmpty ? "音源支持" : "文件大小 \($0.sizeText)" } ?? unavailableText)
                                            .font(.system(size: 12.5))
                                            .foregroundStyle(scheme.onSurfaceVariant)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    if playbackService.preferredQuality == quality {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 22))
                                            .foregroundStyle(scheme.onSecondaryContainer)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 62)
                                .background(
                                    playbackService.preferredQuality == quality
                                        ? scheme.secondaryContainer.opacity(0.72)
                                        : scheme.surfaceContainer,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .disabled(!isAvailable)
                            .opacity(isAvailable ? 1 : 0.46)
                            .accessibilityIdentifier("player-quality-option-\(quality.rawValue)")
                        }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .background(scheme.surfaceContainerLow.ignoresSafeArea())
    }

    private var unavailableText: String {
        track == nil ? "作为下一首播放的质量上限" : "当前曲目未提供这个档位"
    }

    /// 先收起弹层再等解析：重新拿播放地址要走一次网络，让用户对着不动的表等没有意义。
    private func apply(_ quality: Quality) {
        dismiss()
        Task { @MainActor in
            switch await playbackService.setPreferredQuality(quality) {
            case .unchanged:
                toastCenter.show("当前已是 \(quality.title)")
            case let .reloaded(applied):
                toastCenter.show("已切换到 \(applied.title)")
            case .deferred:
                toastCenter.show("下一首将从 \(quality.title) 开始")
            case let .failed(message):
                toastCenter.show("切换失败：\(message)")
            }
        }
    }
}
