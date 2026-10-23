import SwiftUI

struct QualitySheet: View {
    let track: Track?

    @Environment(\.dismiss) private var dismiss
    @Environment(PlaybackService.self) private var playbackService
    @Environment(ToastCenter.self) private var toastCenter
    @Environment(\.m3Scheme) private var scheme
    @State private var entitledCeiling: Quality?

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
                    if let ceiling = entitledCeiling {
                        HStack(spacing: 6) {
                            Image(systemName: "person.badge.key")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(scheme.onSurfaceVariant)
                            Text("账号当前可播上限：\(ceiling.title)")
                                .font(.system(size: 12))
                                .foregroundStyle(scheme.onSurfaceVariant)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)
                        .accessibilityIdentifier("player-quality-ceiling")
                    }
                    if let actual = playbackService.lastActualQuality {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform.badge.checkmark")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(scheme.primary)
                            Text("上次实际播放音质：\(actual.title)")
                                .font(.system(size: 12))
                                .foregroundStyle(scheme.onSurfaceVariant)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.bottom, 6)
                        .accessibilityIdentifier("player-quality-actual")
                    }
                    ForEach(Quality.displayOrder, id: \.self) { quality in
                        let option = options[quality]
                            Button {
                                apply(quality)
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(quality.title)
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(scheme.onSurface)
                                        Text(option.map { $0.sizeText.isEmpty ? "音源标记支持" : "文件大小 \($0.sizeText)" } ?? "从此档位开始，无法获取时逐级降低")
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
                            .accessibilityIdentifier("player-quality-option-\(quality.rawValue)")
                        }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .background(scheme.surfaceContainerLow.ignoresSafeArea())
        .task(id: track?.musicID) { await loadEntitlementCeiling() }
    }

    /// 用 `/api/song/enhance/privilege` 拿到账号在这首歌上的可播上限，超过上限的档位置灰。
    private func loadEntitlementCeiling() async {
        guard let track, track.source == .wy else {
            entitledCeiling = nil
            return
        }
        let client = NetEaseWebClient()
        guard let map = try? await client.privileges(ids: [track.songmid]),
              let entry = map[track.songmid] else {
            entitledCeiling = nil
            return
        }
        let level = (entry["playMaxBrLevel"] as? String)
            ?? (entry["maxBrLevel"] as? String)
            ?? ""
        entitledCeiling = Quality(netEaseLevel: level)
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
