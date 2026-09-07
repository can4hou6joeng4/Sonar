import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    let onClose: () -> Void

    private enum PresentedSheet: String, Identifiable {
        case quality
        var id: String { rawValue }
    }

    @Environment(SonarThemeState.self) private var themeState
    @Environment(UIPlaybackPreferences.self) private var preferences
    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.m3Scheme) private var scheme
    @Environment(\.modelContext) private var modelContext

    @State private var presentedSheet: PresentedSheet?
    @State private var backupDocument: BackupDocument?
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var isReadingBackup = false
    @State private var backupMessage: String?

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

                    sectionTitle("歌单备份")
                    VStack(spacing: 0) {
                        backupButton(icon: "square.and.arrow.up", title: "导出歌单",
                                     subtitle: "将个人歌单保存到文件", id: "settings-export-playlist") {
                            do {
                                backupDocument = BackupDocument(data: try LibraryStore(context: modelContext).exportPersonalPlaylist())
                                isExporting = true
                            } catch {
                                backupMessage = "导出未完成，请稍后重试。"
                            }
                        }
                        backupButton(icon: "square.and.arrow.down", title: "导入歌单",
                                     subtitle: "合并备份中的歌曲，保留现有歌单", id: "settings-import-playlist") {
                            isImporting = true
                        }
                        if isReadingBackup {
                            ProgressView("正在读取备份…")
                                .padding(.vertical, 10)
                        }
                    }
                    .disabled(isReadingBackup)
                    .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)

                    sectionTitle("关于")
                    settingRow(
                        icon: "music.note",
                        title: "Sonar",
                        subtitle: AppVersion.display()
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
        .fileExporter(isPresented: $isExporting, document: backupDocument,
                      contentType: .json, defaultFilename: "Sonar-歌单备份") { result in
            if case .failure = result { backupMessage = "导出未完成，请重试并选择可写入的位置。" }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { importBackup(at: url) }
            if case .failure = result { backupMessage = "暂时无法打开所选文件，请重试。" }
        }
        .alert("歌单备份", isPresented: Binding(
            get: { backupMessage != nil }, set: { if !$0 { backupMessage = nil } }
        )) {
            Button("好", role: .cancel) { backupMessage = nil }
        } message: { Text(backupMessage ?? "") }
    }

    private func backupButton(icon: String, title: String, subtitle: String, id: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            settingRow(icon: icon, title: title, subtitle: subtitle) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(scheme.outline)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func importBackup(at url: URL) {
        isReadingBackup = true
        Task {
            do {
                let data = try await Task.detached(priority: .userInitiated) {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let handle = try FileHandle(forReadingFrom: url)
                    defer { try? handle.close() }
                    let data = try handle.read(upToCount: PlaylistBackup.maximumFileSize + 1) ?? Data()
                    guard data.count <= PlaylistBackup.maximumFileSize else {
                        throw CocoaError(.fileReadTooLarge)
                    }
                    return data
                }.value
                let result = try LibraryStore(context: modelContext).importPersonalPlaylist(from: data)
                backupMessage = "已添加 \(result.insertedCount) 首歌曲，跳过 \(result.skippedCount) 首重复歌曲。歌单现有 \(result.totalCount) 首。"
            } catch let error as PlaylistBackupError {
                backupMessage = error.localizedDescription
            } catch {
                backupMessage = "导入未完成。请选择有效的 Sonar 歌单备份（不超过 10 MB），现有歌单会保留。"
            }
            isReadingBackup = false
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(scheme.onSurface)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭设置")
            .accessibilityHint("返回当前页面")
            .accessibilityIdentifier("settings-drawer-close")
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
