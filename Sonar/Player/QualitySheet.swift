import SwiftUI

struct QualitySheet: View {
    let track: Track

    @Environment(\.dismiss) private var dismiss
    @Environment(UIPlaybackPreferences.self) private var preferences
    @Environment(ToastCenter.self) private var toastCenter
    @Environment(\.m3Scheme) private var scheme

    private var options: [TrackQualityOption] {
        TrackQualityOption.available(for: track)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(title: "播放音质")
                .accessibilityIdentifier("player-quality-sheet")
            if options.isEmpty {
                ContentUnavailableView(
                    "没有可选音质",
                    systemImage: "waveform.badge.exclamationmark",
                    description: Text("音源没有返回可确认的文件大小。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(options) { option in
                            Button {
                                // 偏离规格：PlaybackService 没有单曲音质覆盖契约；这里只持久化用户偏好，
                                // 不能绕过播放层直接替换当前 URL。
                                preferences.preferredQuality = option.quality
                                dismiss()
                                toastCenter.show("音质偏好已设为 \(option.quality.title)")
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(option.quality.title)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(scheme.onSurface)
                                        Text("文件大小 \(option.sizeText)")
                                            .font(.system(size: 12.5))
                                            .foregroundStyle(scheme.onSurfaceVariant)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    if preferences.preferredQuality == option.quality {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 22))
                                            .foregroundStyle(scheme.onSecondaryContainer)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .frame(minHeight: 62)
                                .background(
                                    preferences.preferredQuality == option.quality
                                        ? scheme.secondaryContainer.opacity(0.72)
                                        : scheme.surfaceContainer,
                                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("player-quality-option-\(option.quality.rawValue)")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 20)
                }
            }
        }
        .background(scheme.surfaceContainerLow.ignoresSafeArea())
    }
}
