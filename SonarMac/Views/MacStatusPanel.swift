import AppKit
import SwiftUI

/// The menu-bar popover is the complete browsing surface; it opens no windows.
struct MacStatusPanel: View {
    private enum MusicTab: String, CaseIterable {
        case search, favorites

        var title: String {
            switch self {
            case .search: "搜索"
            case .favorites: "播放列表"
            }
        }

        var symbol: String {
            switch self {
            case .search: "magnifyingglass"
            case .favorites: "music.note.list"
            }
        }
    }

    private struct FavoriteRemovalFeedback {
        let track: Track
        var index: Int
    }

    @Bindable var model: MacAppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var search: SearchViewModel
    @State private var tab: MusicTab?
    @State private var showsSettings = false
    @State private var removalFeedback: [String: FavoriteRemovalFeedback] = [:]
    @FocusState private var searchFocused: Bool

    init(model: MacAppModel) {
        self.model = model
        _search = State(initialValue: SearchViewModel(runtime: model.runtime))
    }

    private var playback: PlaybackService { model.playback }
    private var tracks: [Track] {
        switch tab {
        case .favorites: model.libraryTracks
        case .search: search.results
        case nil: []
        }
    }

    private var displayedTracks: [Track] {
        guard tab == .favorites else { return tracks }
        var result = tracks
        for feedback in removalFeedback.values.sorted(by: { $0.index < $1.index }) {
            guard !result.contains(where: { $0.musicID == feedback.track.musicID }) else { continue }
            result.insert(feedback.track, at: min(feedback.index, result.count))
        }
        return result
    }

    private var removalAnimation: Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.42)
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Label("Sonar", systemImage: "waveform").font(.headline)
                Spacer()
                Button { model.showNotch() } label: { Image(systemName: "macbook") }
                    .help(model.notchEnabled ? "展开灵动岛" : "启用并展开灵动岛")
                    .accessibilityLabel(model.notchEnabled ? "展开灵动岛" : "启用并展开灵动岛")
                Button {
                    showsSettings.toggle()
                    if showsSettings { tab = nil; searchFocused = false }
                } label: { Image(systemName: "slider.horizontal.3") }
                    .foregroundStyle(showsSettings ? Color.accentColor : Color.primary)
                    .help(showsSettings ? "关闭设置" : "打开设置")
                    .accessibilityLabel(showsSettings ? "关闭设置" : "打开设置")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .help("退出 Sonar").accessibilityLabel("退出 Sonar")
            }.buttonStyle(.plain)
            player
            if showsSettings || tab != nil { Divider() }
            if showsSettings {
                settings
                messages
            } else {
                if tab == .search { searchField }
                messages
                if tab != nil {
                    songList.frame(height: 260)
                    Text("\(tracks.count) 首歌曲")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: tab) { _, _ in
            searchFocused = false
            removalFeedback.removeAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sonarStatusPanelDidClose)) { _ in
            tab = nil
            showsSettings = false
            searchFocused = false
            removalFeedback.removeAll()
        }
        .task(id: model.notice) {
            guard let notice = model.notice else { return }
            do { try await Task.sleep(for: .seconds(3)) }
            catch { return }
            if model.notice == notice { model.notice = nil }
        }
    }

    private var browseButtons: some View {
        HStack(spacing: 2) {
            ForEach(MusicTab.allCases, id: \.self) { item in
                Button {
                    showsSettings = false
                    tab = tab == item ? nil : item
                } label: {
                    Image(systemName: item.symbol)
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 24, height: 24)
                        .foregroundStyle(tab == item ? Color.accentColor : Color.primary)
                        .background(tab == item ? Color.accentColor.opacity(0.15) : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tab == item ? "收起\(item.title)" : "显示\(item.title)")
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(tab == item ? [.isSelected] : [])
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.quaternary, in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("搜索与播放列表")
    }

    private var player: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                MacArtworkView(track: playback.queue.current, service: model.artworkService, size: 46, radius: 9)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 10) {
                        Text(playback.queue.current?.title ?? "从一首好歌开始")
                            .fontWeight(.semibold).lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .help(playback.queue.current?.title ?? "从一首好歌开始")
                        MacPlaybackControls(playback: playback)
                    }
                    HStack(spacing: 8) {
                        Text(playback.queue.current?.artist ?? "搜索歌曲，或打开你的歌单")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 0)
                        if let track = playback.queue.current {
                            Button { toggleFavorite(track) } label: {
                                Image(systemName: model.isFavorite(track) ? "heart.fill" : "heart")
                            }.buttonStyle(.plain)
                                .help(model.isFavorite(track) ? "取消收藏当前歌曲" : "收藏当前歌曲")
                                .accessibilityLabel(model.isFavorite(track) ? "取消收藏当前歌曲" : "收藏当前歌曲")
                                .disabled(model.library == nil || removalFeedback[track.musicID] != nil)
                        }
                        browseButtons
                    }
                }
            }
            HStack(spacing: 6) {
                Text(macTime(playback.elapsed)).frame(width: 33, alignment: .leading)
                MacSeekSlider(playback: playback)
                Text(macTime(playback.duration)).frame(width: 33, alignment: .trailing)
            }.font(.caption2).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private var searchField: some View {
        @Bindable var search = search
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索歌曲或歌手", text: $search.query).textFieldStyle(.plain)
                .focused($searchFocused).onSubmit(submitSearch)
                .onChange(of: search.query) { _, _ in search.queryChanged() }
            Button("搜索", action: submitSearch)
                .disabled(search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || search.isLoading)
        }.padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .task {
            await Task.yield()
            guard tab == .search, !Task.isCancelled else { return }
            searchFocused = true
        }
    }

    @ViewBuilder private var messages: some View {
        if model.libraryFailed {
            HStack {
                Text("资料库未能打开，原有数据已保留。").font(.caption)
                Spacer(minLength: 0)
                Button("重试", action: model.retryLibrary)
                Button("导出恢复", action: model.exportRecovery)
            }
        }
        if showsSettings, let message = model.errorMessage {
            HStack {
                Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                Text(message).font(.caption).foregroundStyle(.orange).lineLimit(2)
                Spacer(minLength: 0)
                Button("关闭") { model.errorMessage = nil }
            }
        } else if showsSettings, let notice = model.notice {
            HStack {
                Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
                Text(notice).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                Spacer(minLength: 0)
                Button { model.notice = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("关闭提示")
            }
        } else if case .failed(let message) = playback.state {
            compactMessage(message) { Task { await playback.retryCurrent() } }
        } else if let message = model.errorMessage {
            HStack {
                Text(message).font(.caption).foregroundStyle(.orange).lineLimit(2)
                Spacer(minLength: 0)
                Button("关闭") { model.errorMessage = nil }
            }
        } else if tab == .search, let warning = search.partialSourceWarning {
            compactMessage(warning) { Task { await search.retryFailedSource() } }
        } else if tab == .search, let error = search.errorMessage {
            compactMessage(error, action: submitSearch)
        } else if let notice = model.notice {
            HStack {
                Text(notice).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
                Button { model.notice = nil } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("关闭提示")
            }
        }
    }

    private func compactMessage(_ message: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(message).font(.caption).foregroundStyle(.orange).lineLimit(2)
            Spacer(minLength: 0)
            Button("重试", action: action)
        }
    }

    private var songList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(Array(displayedTracks.enumerated()), id: \.element.musicID) { index, track in
                    let wasRemoved = removalFeedback[track.musicID] != nil
                    HStack(spacing: 8) {
                        Button {
                            let requestedTracks = tracks
                            let fromFavorites = tab == .favorites
                            Task {
                                if fromFavorites {
                                    if let currentIndex = model.libraryTracks.firstIndex(where: { $0.musicID == track.musicID }) {
                                        await model.playFavorites(at: currentIndex)
                                    }
                                } else { await model.play(requestedTracks, at: index) }
                            }
                        } label: {
                            HStack(spacing: 9) {
                                MacArtworkView(track: track, service: model.artworkService, size: 32, radius: 6)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(track.title).lineLimit(1).fontWeight(playback.queue.current?.musicID == track.musicID ? .semibold : .regular)
                                    Text("\(track.artist) · \(track.source.displayName)").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("播放 \(track.title)，\(track.artist)")
                            .disabled(wasRemoved)
                        if wasRemoved {
                            Label("已移除", systemImage: "checkmark.circle.fill")
                                .font(.caption).foregroundStyle(.green)
                                .accessibilityLabel("\(track.title)已移出个人歌单")
                        } else {
                            Button { toggleFavorite(track) } label: {
                                Image(systemName: model.isFavorite(track) ? "heart.fill" : "heart")
                            }
                                .buttonStyle(.plain)
                                .help(model.isFavorite(track) ? "取消收藏 \(track.title)" : "收藏 \(track.title)")
                                .accessibilityLabel(model.isFavorite(track) ? "取消收藏 \(track.title)" : "收藏 \(track.title)")
                                .disabled(model.library == nil)
                        }
                    }.padding(.vertical, 6).padding(.horizontal, 3)
                        .background(wasRemoved ? Color.green.opacity(0.10) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                        .transition(.asymmetric(
                            insertion: .opacity,
                            removal: reduceMotion ? .identity : .opacity.combined(with: .move(edge: .trailing))
                        ))
                        .task(id: wasRemoved) {
                            guard wasRemoved else { return }
                            do { try await Task.sleep(for: .milliseconds(800)) }
                            catch {
                                finishRemovalFeedback(for: track.musicID)
                                return
                            }
                            finishRemovalFeedback(for: track.musicID)
                        }
                }
            }
            .animation(removalAnimation, value: displayedTracks.map(\.musicID))
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if tab == .search, search.isLoading { ProgressView("正在搜索…") }
            else if displayedTracks.isEmpty {
                Text(tab == .search ? (search.hasSearched ? "没有找到歌曲，试试其他关键词。" : "输入歌名或歌手，按回车搜索。") : "歌单里还没有歌曲。")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
            }
        }
    }

    private func toggleFavorite(_ track: Track) {
        guard removalFeedback[track.musicID] == nil else { return }
        let index = tab == .favorites && model.isFavorite(track)
            ? displayedTracks.firstIndex(where: { $0.musicID == track.musicID }) : nil
        model.toggleFavorite(track)
        guard let index, !model.isFavorite(track) else { return }
        removalFeedback[track.musicID] = FavoriteRemovalFeedback(track: track, index: index)
    }

    private func finishRemovalFeedback(for musicID: String) {
        guard let removed = removalFeedback[musicID] else { return }
        withAnimation(removalAnimation) {
            removalFeedback[musicID] = nil
            for key in Array(removalFeedback.keys) {
                if let feedback = removalFeedback[key], feedback.index > removed.index {
                    removalFeedback[key]?.index -= 1
                }
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "macbook")
                        .frame(width: 18).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("灵动岛").fontWeight(.medium)
                        Text("在屏幕顶部显示播放控制").font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Toggle("启用灵动岛", isOn: $model.notchEnabled)
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        .accessibilityLabel("启用灵动岛")
                }
                .padding(12)
            }
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("歌单备份").fontWeight(.medium)
                    Spacer()
                    if model.library != nil {
                        Text("\(model.libraryTracks.count) 首歌曲")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text("只保存歌曲信息；导入会合并已有歌曲并跳过重复项。")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button(action: model.importBackup) {
                        Label("导入备份…", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    Button(action: model.exportBackup) {
                        Label("导出备份…", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.bordered)
                .disabled(model.library == nil)
            }
            .padding(12)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        }
        .font(.callout)
    }

    private func submitSearch() { Task { await search.search(scope: .songs) } }
}
