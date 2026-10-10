import SwiftUI

private struct OnlinePlaylistImporterKey: EnvironmentKey {
    static let defaultValue: OnlinePlaylistImporting? = nil
}

extension EnvironmentValues {
    var onlinePlaylistImporter: OnlinePlaylistImporting? {
        get { self[OnlinePlaylistImporterKey.self] }
        set { self[OnlinePlaylistImporterKey.self] = newValue }
    }
}

struct OnlinePlaylistImportView: View {
    let service: OnlinePlaylistImporting
    let library: LibraryStore
    var artworkService: ArtworkService? = nil
    var onImported: () -> Void = {}
    var onClose: (() -> Void)? = nil

    private struct Request: Identifiable {
        let id = UUID()
        let input: String
        let source: MusicSource
    }

    private enum State {
        case idle
        case loading
        case loaded(OnlinePlaylistPreview)
        case failed(String)
        case imported(PlaylistImportResult)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.m3Scheme) private var scheme
    @State private var input = ""
    @State private var source: MusicSource = .tx
    @State private var request: Request?
    @State private var state: State = .idle
    @State private var existingIDs = Set<String>()
    @State private var saveError: String?
    @FocusState private var inputFocused: Bool
    #if os(iOS)
    @State private var detent: PresentationDetent = .height(500)
    #endif

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch state {
                    case let .imported(result):
                        success(result)
                    case let .loaded(preview):
                        previewSection(preview)
                    default:
                        inputSection
                        switch state {
                        case .loading: loadingStatus
                        case let .failed(message):
                            notice(title: "暂时无法读取", message: message, symbol: "exclamationmark.circle")
                                .accessibilityIdentifier("online-playlist-import-error")
                        default: instructions
                        }
                    }
                    if let saveError {
                        notice(title: "导入未完成", message: saveError, symbol: "exclamationmark.circle")
                            .accessibilityIdentifier("online-playlist-import-save-error")
                    }
                }
                .padding(.horizontal, contentPadding)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            footer
        }
        .foregroundStyle(primaryInk)
        .background(background.ignoresSafeArea())
        .task(id: request?.id) {
            guard let request else { return }
            await read(request)
        }
        .onChange(of: input) { _, _ in reset() }
        .onChange(of: source) { _, _ in reset() }
        #if os(iOS)
        .presentationDetents([.height(500), .large], selection: $detent)
        .onChange(of: displaysPreview) { _, shown in detent = shown ? .large : .height(500) }
        #endif
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 0) {
            #if os(iOS)
            SheetHeader(title: "导入歌单", subtitle: "QQ 音乐 · 网易云音乐")
                .accessibilityIdentifier("online-playlist-import-sheet")
            #else
            VStack(alignment: .leading, spacing: 4) {
                Text("导入歌单").font(.headline).accessibilityIdentifier("online-playlist-import-sheet")
                Text("QQ 音乐 · 网易云音乐").font(.caption).foregroundStyle(secondaryInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, contentPadding)
            .padding(.vertical, 14)
            #endif
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(secondaryInk)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭导入")
            .accessibilityIdentifier("online-playlist-import-close")
            .padding(.trailing, contentPadding)
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("粘贴歌单链接，带上喜欢的音乐。")
                .font(formTitleFont)
            sourcePicker
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "link")
                        .font(.system(size: 16))
                        .foregroundStyle(secondaryInk)
                        .accessibilityHidden(true)
                    TextField("歌单分享链接或 ID", text: $input, axis: .vertical)
                        .lineLimit(1...3)
                        .font(inputFont)
                        .textFieldStyle(.plain)
                        .focused($inputFocused)
                        .onSubmit(startReading)
                        .accessibilityLabel("歌单分享链接或 ID")
                        .accessibilityIdentifier("online-playlist-import-input")
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .submitLabel(.go)
                        #endif
                    if !input.isEmpty {
                        Button { input = ""; inputFocused = true } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(secondaryInk)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("清空歌单链接")
                        .accessibilityIdentifier("online-playlist-import-clear")
                    }
                }
                .padding(.leading, 14)
                .padding(.trailing, input.isEmpty ? 14 : 0)
                .padding(.vertical, 6)
                .frame(minHeight: 52)
                .background(inputFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text("链接自动识别音源；ID 使用上方所选音源。")
                    .font(.system(size: 12))
                    .foregroundStyle(secondaryInk)
            }
        }
    }

    private var sourcePicker: some View {
        Group {
            #if os(iOS)
            HStack(spacing: 0) {
                ForEach(MusicSource.allCases, id: \.self) { option in
                    Button { source = option } label: {
                        Text(option.displayName)
                            .font(.system(size: 14, weight: source == option ? .semibold : .regular))
                            .foregroundStyle(source == option ? scheme.primary : scheme.onSurfaceVariant)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background {
                                if source == option {
                                    Capsule().fill(scheme.surfaceContainer).padding(4)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(source == option ? .isSelected : [])
                    .accessibilityIdentifier("online-playlist-import-source-\(option.rawValue)")
                }
            }
            .background(scheme.appSurface, in: Capsule())
            #else
            Picker("歌单音源", selection: $source) {
                ForEach(MusicSource.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("online-playlist-import-source")
            #endif
        }
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("如何获取歌单链接")
                .font(.system(size: 13, weight: .semibold))
            Label("在原播放器中打开歌单", systemImage: "1.circle")
            Label("点击分享，复制链接后粘贴到这里", systemImage: "2.circle")
            Text("支持公开歌单；私密歌单暂无法读取。")
                .font(.system(size: 12))
        }
        .font(.system(size: 13))
        .foregroundStyle(secondaryInk)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }

    private var loadingStatus: some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small).tint(accent)
            VStack(alignment: .leading, spacing: 4) {
                Text("正在读取歌单…").font(.system(size: 14, weight: .medium))
                Text("歌曲较多时，请稍等片刻。")
                    .font(.system(size: 12)).foregroundStyle(secondaryInk)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(inputFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityIdentifier("online-playlist-import-loading")
    }

    private func previewSection(_ preview: OnlinePlaylistPreview) -> some View {
        let duplicateCount = existingCount(in: preview)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                artwork(preview.tracks.first, size: 68)
                VStack(alignment: .leading, spacing: 5) {
                    Text(preview.reference.source.displayName)
                        .font(.system(size: 12)).foregroundStyle(secondaryInk)
                    Text(preview.name)
                        .font(.system(size: 18, weight: .semibold)).lineLimit(2)
                    Text("共 \(preview.remoteTrackCount) 首 · 已读取 \(preview.tracks.count) 首")
                        .font(.system(size: 12)).foregroundStyle(secondaryInk)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("online-playlist-import-preview")
            HStack(spacing: 8) {
                Text("可新增 \(preview.tracks.count - duplicateCount) 首 · 已收藏 \(duplicateCount) 首")
                    .font(.system(size: 12)).foregroundStyle(secondaryInk)
                Spacer(minLength: 0)
                Button("更换歌单") { reset(); inputFocused = true }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(accent)
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("online-playlist-import-change")
            }
            if preview.isIncomplete {
                notice(title: "歌单未完整读取",
                       message: "\(preview.missingTrackCount) 首未返回，\(preview.invalidTrackCount) 首信息无效。仅导入已读取的歌曲。",
                       symbol: "exclamationmark.triangle")
                    .accessibilityIdentifier("online-playlist-import-incomplete")
            }
            if preview.duplicateTrackCount > 0 {
                Text("歌单中的 \(preview.duplicateTrackCount) 首重复歌曲已合并。")
                    .font(.system(size: 12)).foregroundStyle(secondaryInk)
            }
            if preview.tracks.isEmpty {
                notice(title: "没有可导入的歌曲", message: "可以更换一个公开歌单试试。", symbol: "music.note.list")
            } else {
                Text("歌曲预览")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(secondaryInk)
                LazyVStack(spacing: 0) {
                    ForEach(preview.tracks.prefix(20), id: \.musicID) { track in
                        previewRow(track)
                    }
                }
                #if os(iOS)
                .padding(.horizontal, -contentPadding)
                #endif
                if preview.tracks.count > 20 {
                    Text("另有 \(preview.tracks.count - 20) 首歌曲，将按原歌单顺序一并导入。")
                        .font(.system(size: 12)).foregroundStyle(secondaryInk)
                }
            }
        }
    }

    @ViewBuilder private func artwork(_ track: Track?, size: CGFloat) -> some View {
        #if os(iOS)
        PlayerArtwork(track: track, size: size, cornerRadius: 8)
        #else
        MacArtworkView(track: track, service: artworkService, size: size, radius: 6)
        #endif
    }

    @ViewBuilder private func previewRow(_ track: Track) -> some View {
        #if os(iOS)
        SongRow(track: track, trailing: .collectionStatus(existingIDs.contains(track.musicID)))
        #else
        HStack(spacing: 10) {
            artwork(track, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title).lineLimit(1)
                Text([track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(secondaryInk).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if existingIDs.contains(track.musicID) {
                Image(systemName: "checkmark").foregroundStyle(secondaryInk)
                    .accessibilityLabel("已收藏，导入时跳过")
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        #endif
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Rectangle().fill(separator).frame(height: 0.5)
            VStack(spacing: 10) {
                switch state {
                case let .loaded(preview) where !preview.tracks.isEmpty:
                    Text("合并到个人歌单，保留已有歌曲并跳过重复项。")
                        .font(.system(size: 12)).foregroundStyle(secondaryInk)
                        .multilineTextAlignment(.center)
                    primaryButton(preview.isIncomplete ? "导入已读取的 \(preview.tracks.count) 首" : "导入歌单",
                                  symbol: "square.and.arrow.down", id: "online-playlist-import-confirm") { save(preview) }
                case .loaded:
                    primaryButton("更换歌单", symbol: "link", id: "online-playlist-import-replace") { reset(); inputFocused = true }
                case .imported:
                    primaryButton("完成", symbol: "checkmark", id: "online-playlist-import-done", action: close)
                case .loading:
                    Button("取消读取", action: reset)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(secondaryInk)
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("online-playlist-import-cancel")
                default:
                    primaryButton(readButtonTitle, symbol: "arrow.right", id: "online-playlist-import-read",
                                  enabled: !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                                  action: startReading)
                }
            }
            .padding(.horizontal, contentPadding)
            .padding(.bottom, 16)
        }
        .background(background)
    }

    @ViewBuilder private func primaryButton(_ title: String, symbol: String, id: String,
                                            enabled: Bool = true, action: @escaping () -> Void) -> some View {
        #if os(iOS)
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(scheme.onPrimary)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(scheme.primary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.bounce)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityIdentifier(id)
        #else
        HStack {
            Spacer()
            Button(title, action: action)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!enabled)
                .accessibilityIdentifier(id)
        }
        #endif
    }

    private func notice(title: String, message: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(message).font(.system(size: 12)).foregroundStyle(secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(inputFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func success(_ result: PlaylistImportResult) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 64, height: 64)
                .background(inputFill, in: Circle())
                .accessibilityHidden(true)
            Text("歌单已导入").font(.system(size: 18, weight: .semibold))
            HStack(spacing: 36) {
                importCount(result.insertedCount, label: "新增歌曲")
                importCount(result.skippedCount, label: "跳过已收藏")
            }
            Text("个人歌单现有 \(result.totalCount) 首歌曲。")
                .font(.system(size: 12)).foregroundStyle(secondaryInk)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("online-playlist-import-success")
    }

    private func importCount(_ count: Int, label: String) -> some View {
        VStack(spacing: 5) {
            Text("\(count)").font(.system(size: 24, weight: .semibold)).monospacedDigit()
            Text(label).font(.system(size: 12)).foregroundStyle(secondaryInk)
        }
    }

    private var isLoading: Bool { if case .loading = state { true } else { false } }

    private var displaysPreview: Bool { if case .loaded = state { true } else { false } }

    private var readButtonTitle: String {
        if case .failed = state { return "重新读取" }
        return "读取歌单"
    }

    private func existingCount(in preview: OnlinePlaylistPreview) -> Int {
        preview.tracks.filter { existingIDs.contains($0.musicID) }.count
    }

    private var contentPadding: CGFloat {
        #if os(iOS)
        NCMDesignTokens.Layout.horizontalPadding
        #else
        16
        #endif
    }

    private var formTitleFont: Font {
        #if os(iOS)
        .system(size: 15, weight: .semibold)
        #else
        .callout.weight(.medium)
        #endif
    }

    private var inputFont: Font {
        #if os(iOS)
        .system(size: 15)
        #else
        .callout
        #endif
    }

    private var primaryInk: Color {
        #if os(iOS)
        scheme.onSurface
        #else
        .primary
        #endif
    }

    private var secondaryInk: Color {
        #if os(iOS)
        scheme.onSurfaceVariant
        #else
        .secondary
        #endif
    }

    private var accent: Color {
        #if os(iOS)
        scheme.primary
        #else
        .accentColor
        #endif
    }

    private var inputFill: Color {
        #if os(iOS)
        scheme.appSurface
        #else
        Color.primary.opacity(0.07)
        #endif
    }

    private var separator: Color {
        #if os(iOS)
        scheme.outlineVariant
        #else
        Color(nsColor: .separatorColor)
        #endif
    }

    private var background: Color {
        #if os(iOS)
        scheme.surfaceContainerLow
        #else
        .clear
        #endif
    }

    private func close() {
        if let onClose { onClose() }
        else { dismiss() }
    }

    private func reset() {
        request = nil
        state = .idle
        existingIDs = []
        saveError = nil
    }

    private func startReading() {
        guard !isLoading, !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        inputFocused = false
        saveError = nil
        state = .loading
        request = Request(input: input, source: source)
    }

    @MainActor private func read(_ requested: Request) async {
        do {
            let preview = try await service.preview(requested.input, source: requested.source)
            try Task.checkCancellation()
            guard request?.id == requested.id else { return }
            existingIDs = Set(try library.playlists(includeSystem: false).flatMap { $0.items.map(\.track.musicId) })
            state = .loaded(preview)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, request?.id == requested.id else { return }
            state = .failed(error.localizedDescription)
        }
    }

    @MainActor private func save(_ preview: OnlinePlaylistPreview) {
        do {
            let result = try library.importPersonalPlaylist(from: preview.backupData())
            state = .imported(result)
            onImported()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
