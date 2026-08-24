import SwiftUI

struct SettingsView: View {
    private enum PresentedSheet: String, Identifiable {
        case quality
        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(SonarThemeState.self) private var themeState
    @Environment(UIPlaybackPreferences.self) private var preferences
    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.m3Scheme) private var scheme

    @State private var presentedSheet: PresentedSheet?

    var body: some View {
        @Bindable var themeState = themeState
        @Bindable var preferences = preferences

        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(spacing: 0) {
                    sectionTitle("外观")
                    VStack(spacing: 14) {
                        Picker("外观", selection: $themeState.appearanceMode) {
                            Text("浅色").tag(AppearanceMode.light)
                            Text("深色").tag(AppearanceMode.dark)
                            Text("跟随").tag(AppearanceMode.system)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("settings-appearance-mode")

                        settingRow(
                            icon: "photo.on.rectangle.angled",
                            title: "播放页封面取色",
                            subtitle: "用当前封面生成播放器背景"
                        ) {
                            Toggle("播放页封面取色", isOn: $preferences.coverAccentEnabled)
                                .labelsHidden()
                                .accessibilityIdentifier("settings-cover-accent-toggle")
                        }
                    }
                    .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)

                    sectionTitle("播放")
                    Button {
                        presentedSheet = .quality
                    } label: {
                        settingRow(
                            icon: "waveform",
                            title: "播放音质",
                            subtitle: playbackService.preferredQuality.title
                        ) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(scheme.outline)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
                    .accessibilityIdentifier("settings-quality-button")

                    sectionTitle("关于")
                    settingRow(
                        icon: "music.note",
                        title: "Sonar",
                        subtitle: "版本 1.0"
                    ) {
                        EmptyView()
                    }
                    .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
                    .padding(.bottom, 30)
                }
            }
            .scrollIndicators(.hidden)
        }
        .background(scheme.appSurface.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $presentedSheet) { _ in
            QualitySheet(track: playbackService.queue.current)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(scheme.onSurface)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回")
            Text("设置")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(scheme.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(scheme.onSurfaceVariant)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
            .padding(.top, 22)
            .padding(.bottom, 10)
    }

    private func settingRow<Trailing: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(scheme.primary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 16))
                    .foregroundStyle(scheme.onSurface)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(scheme.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing()
        }
        .frame(minHeight: 58)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(scheme.outlineVariant)
                .frame(height: 0.5)
                .padding(.leading, 42)
        }
    }
}
