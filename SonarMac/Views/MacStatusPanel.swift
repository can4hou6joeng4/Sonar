import AppKit
import SwiftUI

/// The menu-bar popover is the complete browsing surface; it opens no windows.
struct MacStatusPanel: View {
    private enum MusicTab: String, CaseIterable {
        case search, favorites, lyrics

        var title: String {
            switch self {
            case .search: "搜索"
            case .favorites: "播放列表"
            case .lyrics: "歌词"
            }
        }

        var symbol: String {
            switch self {
            case .search: "magnifyingglass"
            case .favorites: "music.note.list"
            case .lyrics: "quote.bubble"
            }
        }
    }

    private struct FavoriteRemovalFeedback {
        let track: Track
        var index: Int
    }

    private struct ImportPresentation: Identifiable {
        let id = UUID()
        let library: LibraryStore
    }

    @Bindable var model: MacAppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var search: SearchViewModel
    @State private var tab: MusicTab?
    @State private var showsSettings = false
    @State private var importPresentation: ImportPresentation?
    @State private var removalFeedback: [String: FavoriteRemovalFeedback] = [:]
    @State private var catalogPath: [MacCatalogDestination] = []
    @State private var qualityNotice: String?
    @FocusState private var searchFocused: Bool

    init(model: MacAppModel) {
        self.model = model
        _search = State(initialValue: SearchViewModel(runtime: model.runtime))
    }

    private var playback: PlaybackService { model.playback }
    private var tracks: [Track] {
        switch tab {
        case .favorites: model.libraryTracks
        case .search: search.selectedScope == .songs ? search.results : []
        case .lyrics, nil: []
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
                if let presentation = importPresentation {
                    OnlinePlaylistImportView(service: model.onlinePlaylistImporter, library: presentation.library,
                                             artworkService: model.artworkService, onImported: model.reloadLibrary,
                                             onClose: { importPresentation = nil })
                        .id(presentation.id)
                        .frame(height: 440)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    settings
                    messages
                }
            } else {
                if tab == .search {
                    searchField
                    if catalogPath.isEmpty { scopePicker }
                }
                messages
                if tab == .lyrics {
                    lyricsSection.frame(height: 300)
                } else if tab != nil {
                    if tab == .search, !catalogPath.isEmpty, let destination = catalogPath.last {
                        MacPanelCatalogView(model: model, destination: destination, push: openCatalog, back: closeCatalog)
                            .frame(height: 300)
                    } else {
                        resultsSection.frame(height: 260)
                        if !(tab == .search && !search.hasSearched) {
                            Text(resultSummary)
                                .font(.caption).foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: tab) { _, _ in
            searchFocused = false
            catalogPath = []
            removalFeedback.removeAll()
        }
        .onChange(of: showsSettings) { _, shown in
            if !shown { importPresentation = nil }
        }
        .onReceive(NotificationCenter.default.publisher(for: .sonarStatusPanelDidClose)) { _ in
            tab = nil
            showsSettings = false
            importPresentation = nil
            searchFocused = false
            catalogPath = []
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
            TextField("搜索歌曲、歌手或专辑", text: $search.query).textFieldStyle(.plain)
                .focused($searchFocused).onSubmit(submitSearch)
                .onChange(of: search.query) { _, _ in
                    catalogPath = []
                    // 中文/日文组合输入期间不请求联想，等上屏后再刷新。
                    guard !MacTextInput.isComposing else { return }
                    search.queryChanged()
                }
            Button("搜索", action: submitSearch)
                .disabled(search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || search.isLoading)
        }.padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .task {
            await Task.yield()
            guard tab == .search, !Task.isCancelled else { return }
            searchFocused = true
            await search.loadHotSearchesIfNeeded()
        }
    }

    private var scopePicker: some View {
        @Bindable var search = search
        return Picker("搜索分类", selection: $search.selectedScope) {
            ForEach(SearchScope.availableCases) { Text($0.rawValue).tag($0) }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .labelsHidden()
        .onChange(of: search.selectedScope) { _, scope in
            catalogPath = []
            Task { await search.loadScopeIfNeeded(scope) }
        }
    }

    @ViewBuilder private var resultsSection: some View {
        switch tab {
        case .favorites:
            songList
        case .search:
            switch search.selectedScope {
            case .songs:
                if search.hasSearched { songList } else { searchDiscovery }
            case .artists:
                artistResultsView
            case .albums:
                albumResultsView
            case .playlists:
                playlistResultsView
            }
        case .lyrics, nil:
            EmptyView()
        }
    }

    private var resultSummary: String {
        guard let tab else { return "" }
        switch tab {
        case .favorites:
            return "\(model.libraryTracks.count) 首歌曲"
        case .lyrics:
            return ""
        case .search:
            switch search.selectedScope {
            case .songs: return "\(search.results.count) 首歌曲"
            case .artists: return "\(search.artistResults.count) 位歌手"
            case .albums: return "\(search.albumResults.count) 张专辑"
            case .playlists: return "\(search.playlistResults.count) 个歌单"
            }
        }
    }

    private var searchDiscovery: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !search.query.isEmpty, !search.suggestions.isEmpty {
                    Text("搜索建议").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(search.suggestions.prefix(5), id: \.self) { suggestion in
                        Button { search.query = suggestion; submitSearch() } label: {
                            Label(suggestion, systemImage: "magnifyingglass")
                                .font(.callout)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain)
                    }
                }
                if !search.history.isEmpty {
                    HStack {
                        Text("搜索历史").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button("清空") { search.clearHistory() }.controlSize(.mini)
                    }
                    chips(search.history)
                }
                Text("热门搜索").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                chips(Array(search.hotSearches.prefix(8)))
            }
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
    }

    private func chips(_ values: [String]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], alignment: .leading, spacing: 6) {
            ForEach(values, id: \.self) { value in
                Button { search.query = value; submitSearch() } label: {
                    Text(value).font(.caption).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain)
            }
        }
    }

    private var artistResultsView: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(search.visibleArtistResults, id: \.stableID) { artist in
                    Button { openCatalog(.artist(artist)) } label: {
                        HStack(spacing: 9) {
                            MacArtworkView(url: artist.imageURL, size: 32, radius: 16)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(artist.name).lineLimit(1)
                                Text(artistMeta(artist)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 5).padding(.horizontal, 3)
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
                if search.canExpandArtistResults {
                    Button(search.isLoadingMoreArtists ? "正在载入…" : "显示更多歌手") {
                        Task { await search.expandArtistResults() }
                    }
                    .controlSize(.small)
                    .disabled(search.isLoadingMoreArtists)
                }
                ForEach(search.artistExpansionWarnings, id: \.self) { source in
                    MacInlineError(message: "\(source.displayName) 更多歌手载入失败") {
                        Task { await search.retryArtistExpansion(source) }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .overlay {
            if search.isLoadingArtists { ProgressView().controlSize(.small) }
            else if search.artistResults.isEmpty { hint("没有找到歌手", "试试完整的歌手名。") }
        }
    }

    private var albumResultsView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 12) {
                ForEach(search.albumResults, id: \.stableID) { album in
                    Button { openCatalog(.album(album)) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            MacArtworkView(url: album.imageURL, size: 96, radius: 8)
                            Text(album.name).font(.caption).lineLimit(2)
                            Text(album.artist).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
        .overlay {
            if search.isLoadingAlbums { ProgressView().controlSize(.small) }
            else if search.albumResults.isEmpty { hint("没有找到专辑", "试试专辑名或歌手名。") }
        }
    }

    private var playlistResultsView: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 12) {
                ForEach(search.playlistResults, id: \.key) { playlist in
                    Button { openCatalog(.playlist(playlist)) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            MacArtworkView(url: playlist.img, size: 96, radius: 8)
                            Text(playlist.name).font(.caption).lineLimit(2)
                            Text(playlist.author.isEmpty ? playlist.source.displayName : playlist.author)
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
        .overlay {
            if search.isLoadingPlaylists { ProgressView().controlSize(.small) }
            else if search.playlistResults.isEmpty { hint("没有找到歌单", "试试歌单名、主题或歌手名。") }
        }
    }

    @ViewBuilder private var lyricsSection: some View {
        if let lyrics = model.lyrics, !lyrics.lines.isEmpty {
            MacPanelLyricsView(document: lyrics, playback: playback)
        } else {
            VStack(spacing: 6) {
                Text(playback.queue.current == nil ? "尚未播放" : "暂无歌词")
                    .font(.callout).foregroundStyle(.secondary)
                Text(playback.queue.current == nil ? "选择一首歌后，这里会显示同步歌词。" : "正在等待这首歌的歌词。")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func hint(_ title: String, _ detail: String) -> some View {
        VStack(spacing: 4) {
            Text(title).font(.callout).foregroundStyle(.secondary)
            Text(detail).font(.caption2).foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.center)
        .padding()
    }

    private func artistMeta(_ artist: ArtistSummary) -> String {
        var parts = [artist.source.displayName]
        if let count = artist.songCount, count > 0 { parts.append("\(count) 首") }
        if let count = artist.albumCount, count > 0 { parts.append("\(count) 张专辑") }
        return parts.joined(separator: " · ")
    }

    private func openCatalog(_ destination: MacCatalogDestination) {
        searchFocused = false
        catalogPath.append(destination)
    }

    private func closeCatalog() {
        guard !catalogPath.isEmpty else { return }
        catalogPath.removeLast()
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
        } else if tab == .search, let error = search.errorMessage {
            compactMessage(error, action: submitSearch)
        } else if tab == .search, let source = search.songSourceWarnings.first {
            compactMessage("\(source.displayName)暂不可用，已显示其他音源结果") {
                Task { await search.retryFailedSource(source) }
            }
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
                    PanelSongRow(
                        track: track,
                        model: model,
                        playback: playback,
                        wasRemoved: wasRemoved,
                        onPlay: { play(track: track, at: index) },
                        onToggleFavorite: { toggleFavorite(track) }
                    )
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
                if tab == .search {
                    hint("没有找到歌曲", "试试其他关键词。")
                } else {
                    VStack(spacing: 8) {
                        Text("歌单里还没有歌曲。")
                            .font(.callout).foregroundStyle(.secondary)
                        Button(action: model.importLocalMusic) {
                            Label("导入本地音乐", systemImage: "folder.badge.plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding()
                }
            }
        }
    }

    private func play(track: Track, at index: Int) {
        let requestedTracks = tracks
        let fromFavorites = tab == .favorites
        Task {
            if fromFavorites {
                if let currentIndex = model.libraryTracks.firstIndex(where: { $0.musicID == track.musicID }) {
                    await model.playFavorites(at: currentIndex)
                }
            } else {
                await model.play(requestedTracks, at: index)
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

            playbackSettings

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    model.importLocalMusic()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "folder.badge.plus")
                            .frame(width: 18).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("导入本地音乐").fontWeight(.medium)
                            Text("音频文件或文件夹 (MP3, FLAC, M4A, WAV 等)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.library == nil)
                .accessibilityIdentifier("mac-settings-import-local-music")
                Divider()
                Button {
                    if let library = model.library { importPresentation = ImportPresentation(library: library) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "music.note.list")
                            .frame(width: 18).foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("从其他播放器导入").fontWeight(.medium)
                            Text("网易云公开歌单")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(model.library == nil)
                .accessibilityIdentifier("mac-settings-import-online-playlist")
                Divider()
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

    private var playbackSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("音质").fontWeight(.medium)
                    Text("从这一档开始，缺档自动降级").font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Picker("首选音质", selection: qualityBinding) {
                    ForEach(Quality.descendingOrder, id: \.self) { Text($0.macTitle).tag($0) }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 150)
                .accessibilityIdentifier("mac-settings-quality")
            }
            if let actual = playback.lastActualQuality {
                Text("上次实际播放：\(actual.macTitle)")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let qualityNotice {
                Text(qualityNotice).font(.caption2).foregroundStyle(.secondary)
            }
            Divider()
            HStack(spacing: 10) {
                Text("播放速度").fontWeight(.medium)
                Spacer(minLength: 8)
                Picker("播放速度", selection: rateBinding) {
                    ForEach(Self.playbackRates, id: \.self) { rate in
                        Text(String(format: "%.2gx", rate)).tag(rate)
                    }
                }
                .labelsHidden()
                .controlSize(.small)
                .frame(width: 80)
                .accessibilityIdentifier("mac-settings-rate")
            }
            Divider()
            HStack(spacing: 10) {
                Text("定时关闭").fontWeight(.medium)
                Spacer(minLength: 8)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    sleepMenu
                }
            }
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private var sleepMenu: some View {
        Menu(model.sleepTimer.remainingText ?? "关闭") {
            Button("关闭定时") { model.sleepTimer.cancel() }
            Divider()
            ForEach(Self.sleepMinutes, id: \.self) { minutes in
                Button("\(minutes) 分钟") {
                    let playback = model.playback
                    model.sleepTimer.start(minutes: minutes) {
                        playback.pause()
                    }
                }
            }
        }
        .controlSize(.small)
        .fixedSize()
        .accessibilityIdentifier("mac-settings-sleep-timer")
    }

    private static let playbackRates: [Float] = [0.75, 1, 1.25, 1.5, 2]
    private static let sleepMinutes = [15, 30, 60, 90]

    private var qualityBinding: Binding<Quality> {
        Binding(get: { playback.preferredQuality }) { value in
            Task { await applyQuality(value) }
        }
    }

    private var rateBinding: Binding<Float> {
        Binding(get: { playback.playbackRate }) { value in
            playback.setPlaybackRate(value)
        }
    }

    private func applyQuality(_ quality: Quality) async {
        switch await playback.setPreferredQuality(quality) {
        case .unchanged:
            qualityNotice = "已使用该音质设置。"
        case .reloaded:
            qualityNotice = "已按新音质重新加载当前歌曲。"
        case .deferred:
            qualityNotice = "下一首歌曲将使用该音质。"
        case .failed(let message):
            qualityNotice = message
        }
    }

    private func submitSearch() { Task { await search.search() } }
}

/// SwiftUI 的 macOS 文本框在拼音/日文组合输入时也会改写绑定，这里读取字段编辑器判断是否仍在组合。
private enum MacTextInput {
    static var isComposing: Bool {
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return false }
        return editor.hasMarkedText()
    }
}

/// 面板歌曲行：把已下架 / 不可用音源的判断收在一处，避免正文表达式过度膨胀。
private struct PanelSongRow: View {
    let track: Track
    let model: MacAppModel
    let playback: PlaybackService
    let wasRemoved: Bool
    let onPlay: () -> Void
    let onToggleFavorite: () -> Void

    private var isDown: Bool { !track.isPlayable }
    private var unplayable: Bool { isDown || !track.source.isEnabled }
    private var isCurrent: Bool { playback.queue.current?.musicID == track.musicID }
    private var isFavorite: Bool { model.isFavorite(track) }

    var body: some View {
        HStack(spacing: 8) {
            playButton
            if wasRemoved {
                Label("已移除", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .accessibilityLabel("\(track.title)已移出个人歌单")
            } else {
                favoriteButton
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 3)
    }

    private var playButton: some View {
        Button(action: onPlay) {
            HStack(spacing: 9) {
                MacArtworkView(track: track, service: model.artworkService, size: 32, radius: 6)
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .lineLimit(1)
                        .fontWeight(isCurrent ? .semibold : .regular)
                    meta
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("播放 \(track.title)，\(track.artist)")
        .accessibilityHint(unplayable ? "该歌曲当前不可播放" : "")
        .disabled(wasRemoved || unplayable)
    }

    private var meta: some View {
        HStack(spacing: 5) {
            Text("\(track.artist) · \(track.source.displayName)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if isDown {
                MacStatusBadge(title: "已下架")
            } else if !track.source.isEnabled {
                MacStatusBadge(title: "不可用")
            }
        }
    }

    private var favoriteButton: some View {
        Button(action: onToggleFavorite) {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
        }
        .buttonStyle(.plain)
        .help(isFavorite ? "取消收藏 \(track.title)" : "收藏 \(track.title)")
        .accessibilityLabel(isFavorite ? "取消收藏 \(track.title)" : "收藏 \(track.title)")
        .disabled(model.library == nil)
    }
}
