import SwiftUI

struct SettingsView: View {
    @Environment(SonarThemeState.self) private var themeState
    @Environment(UIPlaybackPreferences.self) private var preferences
    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.m3Scheme) private var scheme

    @State private var qualityTrack: Track?

    var body: some View {
        @Bindable var themeState = themeState
        @Bindable var preferences = preferences

        VStack(spacing: 0) {
            Text("设置")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(scheme.onSurface)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 0) {
                    sectionTitle("外观")
                    VStack(spacing: 22) {
                        SettingsLabel(
                            icon: "paintpalette",
                            title: "主题模式",
                            subtitle: "浅色 / 深色 / 跟随系统"
                        )

                        Picker("主题模式", selection: $themeState.appearanceMode) {
                            Label("浅色", systemImage: "sun.max").tag(AppearanceMode.light)
                            Label("深色", systemImage: "moon").tag(AppearanceMode.dark)
                            Label("跟随系统", systemImage: "circle.lefthalf.filled").tag(AppearanceMode.system)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("settings-appearance-mode")

                        SettingsLabel(
                            icon: "checkmark",
                            title: "主题颜色",
                            subtitle: "用于生成应用的静态 Material 3 配色",
                            bubbleColor: themeState.accent,
                            bubbleForeground: .white
                        )

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(ThemeSeedPreset.allCases) { preset in
                                    Button {
                                        themeState.usePreset(preset)
                                    } label: {
                                        Circle()
                                            .fill(Color(hex: preset.hex) ?? .blue)
                                            .frame(width: 38, height: 38)
                                            .overlay {
                                                if themeState.seedSource == .preset,
                                                   themeState.selectedPreset == preset {
                                                    Image(systemName: "checkmark")
                                                        .font(.system(size: 16, weight: .bold))
                                                        .foregroundStyle(.white)
                                                }
                                            }
                                            .overlay {
                                                Circle().stroke(.black.opacity(0.12), lineWidth: 1)
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(preset.name)
                                    .accessibilityIdentifier("settings-seed-\(preset.rawValue)")
                                }
                            }
                        }

                        HStack(spacing: 18) {
                            SettingsLabel(
                                icon: "wand.and.stars",
                                title: "封面动态色",
                                subtitle: themeState.seedSource == .artwork
                                    ? "从当前曲目封面取色生成完整主题"
                                    : "使用上面选定的主题色"
                            )
                            Toggle("封面动态色", isOn: artworkSeedBinding)
                                .labelsHidden()
                                .accessibilityIdentifier("settings-artwork-color-toggle")
                        }
                    }
                    .settingsCard(scheme: scheme)

                    sectionTitle("播放")
                    VStack(spacing: 22) {
                        HStack(spacing: 18) {
                            SettingsLabel(
                                icon: "captions.bubble",
                                title: "显示迷你歌词",
                                subtitle: "在封面页左下角显示三行歌词"
                            )
                            Toggle("显示迷你歌词", isOn: $preferences.miniLyricsEnabled)
                                .labelsHidden()
                                .accessibilityIdentifier("settings-mini-lyrics-toggle")
                        }

                        HStack(spacing: 18) {
                            SettingsLabel(
                                icon: "waveform.badge.magnifyingglass",
                                title: "播放音质",
                                subtitle: "\(playbackService.preferredQuality.title) 起，自动选可用的最高档"
                            )
                            Button("切换") {
                                qualityTrack = playbackService.queue.current
                            }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(scheme.onSecondaryContainer)
                            .padding(.horizontal, 18)
                            .frame(minHeight: 40)
                            .background(scheme.secondaryContainer, in: Capsule())
                            .disabled(playbackService.queue.current == nil)
                        }

                        HStack(spacing: 18) {
                            SettingsLabel(
                                icon: "sparkles",
                                title: "动效",
                                subtitle: "关掉后所有过渡与弹簧立即到位"
                            )
                            Toggle("动效", isOn: $preferences.motionEnabled)
                                .labelsHidden()
                                .accessibilityIdentifier("settings-motion-toggle")
                        }
                    }
                    .settingsCard(scheme: scheme)

                    sectionTitle("关于")
                    SettingsLabel(
                        icon: "music.note",
                        title: "Sonar",
                        subtitle: "在深水里靠声音辨路 · 版本 1.0"
                    )
                    .settingsCard(scheme: scheme)
                    .padding(.bottom, 24)
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(scheme.appSurface.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $qualityTrack) { track in
            QualitySheet(track: track)
                .presentationDetents([.fraction(0.72)])
                .presentationDragIndicator(.visible)
        }
    }

    private var artworkSeedBinding: Binding<Bool> {
        Binding(
            get: { themeState.seedSource == .artwork },
            set: { enabled in
                if enabled {
                    themeState.useArtworkSeed()
                } else {
                    themeState.usePreset(themeState.selectedPreset)
                }
            }
        )
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(scheme.onSurfaceVariant)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 8)
    }
}

private struct SettingsLabel: View {
    let icon: String
    let title: String
    let subtitle: String
    var bubbleColor: Color?
    var bubbleForeground: Color?

    @Environment(\.m3Scheme) private var scheme

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(bubbleForeground ?? scheme.onSecondaryContainer)
                .frame(width: 42, height: 42)
                .background(bubbleColor ?? scheme.secondaryContainer, in: Circle())
                .overlay {
                    if bubbleColor != nil {
                        Circle().stroke(scheme.outlineVariant, lineWidth: 1)
                    }
                }
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(scheme.onSurface)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(scheme.outline)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private extension View {
    func settingsCard(scheme: M3Scheme) -> some View {
        padding(.horizontal, 16)
            .padding(.vertical, 18)
            .background(scheme.surfaceContainerLow, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(scheme.outlineVariant.opacity(0.46), lineWidth: 1)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 14)
    }
}
