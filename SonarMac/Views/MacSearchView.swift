import SwiftUI

struct MacSearchView: View {
    let model: MacAppModel
    @Bindable var search: SearchViewModel
    let focusRequest: Int
    let open: (MacCatalogDestination) -> Void
    @FocusState private var focused: Bool
    @State private var loadedHotSearches = false

    private var isLoading: Bool {
        switch search.selectedScope {
        case .songs: search.isLoading
        case .artists: search.isLoadingArtists
        case .playlists: search.isLoadingPlaylists
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 16) {
                Text("找到你的下一首心动").font(.largeTitle.bold())
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("歌曲、歌手或歌单", text: $search.query).textFieldStyle(.plain)
                        .focused($focused).onSubmit { submit() }
                        .onChange(of: search.query) { _, _ in search.queryChanged() }
                    if !search.query.isEmpty {
                        Button { search.query = ""; focused = true } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).help("清除搜索")
                    }
                    Button("搜索") { submit() }
                        .disabled(search.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }.padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                Picker("搜索范围", selection: $search.selectedScope) {
                    ForEach(SearchScope.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(width: 290)
                    .onChange(of: search.selectedScope) { _, scope in Task { await search.loadScopeIfNeeded(scope) } }
                if let warning = search.partialSourceWarning, search.selectedScope == .songs {
                    MacInlineError(message: warning) { Task { await search.retryFailedSource() } }
                }
                if let error = search.errorMessage { MacInlineError(message: error, retry: submit) }
                if search.selectedScope == .artists, !search.artistSourceWarnings.isEmpty {
                    ForEach(search.artistSourceWarnings, id: \.self) { source in
                        MacInlineError(message: "\(source.displayName) 歌手搜索暂不可用") {
                            Task { await search.retryArtistSource(source) }
                        }
                    }
                }
            }.padding(.horizontal, 26).padding(.top, 26)

            if isLoading {
                ProgressView("正在搜索…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !search.hasSearched {
                suggestions
            } else {
                results
            }
        }.task {
            focused = true
            await search.loadHotSearchesIfNeeded()
            loadedHotSearches = true
        }
        .onChange(of: focusRequest) { _, _ in focused = true }
    }

    private func submit() { Task { await search.search() } }

    private var suggestions: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                if !search.suggestions.isEmpty {
                    Text("搜索建议").font(.headline)
                    ForEach(search.suggestions, id: \.self) { suggestion in
                        Button { search.query = suggestion; submit() } label: {
                            Label(suggestion, systemImage: "magnifyingglass").frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.plain).padding(.vertical, 6)
                    }
                } else if loadedHotSearches, search.hotSearchErrorMessage == nil {
                    Text("热门搜索").font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), alignment: .leading)], alignment: .leading, spacing: 12) {
                        ForEach(Array(search.hotSearches.prefix(12).enumerated()), id: \.offset) { index, word in
                            Button { search.query = word; submit() } label: {
                                HStack {
                                    Text(String(format: "%02d", index + 1)).foregroundStyle(.tertiary).monospacedDigit()
                                    Text(word).lineLimit(1)
                                    Spacer(minLength: 0)
                                }.padding(10).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                        }
                    }
                } else {
                    MacEmptyState(title: "搜索你喜欢的音乐", description: "按回车搜索歌曲，或切换到歌手与歌单。", symbol: "magnifyingglass")
                        .frame(height: 260)
                }
            }.padding(26)
        }
    }

    @ViewBuilder private var results: some View {
        switch search.selectedScope {
        case .songs:
            if search.results.isEmpty {
                MacEmptyState(title: "没有找到歌曲", description: "试试更短的歌名或其他关键词。", symbol: "magnifyingglass")
            } else { MacTrackTable(model: model, tracks: search.results) }
        case .artists:
            if search.artistResults.isEmpty {
                MacEmptyState(title: "没有找到歌手", description: "尝试输入完整的歌手名。", symbol: "person")
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 20)], spacing: 24) {
                            ForEach(search.visibleArtistResults, id: \.stableID) { artist in
                                Button { open(.artist(artist)) } label: {
                                    VStack(spacing: 10) {
                                        MacArtworkView(url: artist.imageURL, size: 125, radius: 63)
                                        Text(artist.name).fontWeight(.medium).lineLimit(1)
                                        Text(artist.source.displayName).font(.caption).foregroundStyle(.secondary)
                                    }.frame(maxWidth: .infinity)
                                }.buttonStyle(.plain)
                            }
                        }
                        if search.canExpandArtistResults {
                            Button(search.isLoadingMoreArtists ? "正在载入…" : "显示更多歌手") {
                                Task { await search.expandArtistResults() }
                            }.disabled(search.isLoadingMoreArtists)
                        }
                        ForEach(search.artistExpansionWarnings, id: \.self) { source in
                            MacInlineError(message: "\(source.displayName) 更多歌手载入失败") { Task { await search.retryArtistExpansion(source) } }
                        }
                    }.padding(26)
                }
            }
        case .playlists:
            if search.playlistResults.isEmpty {
                MacEmptyState(title: "没有找到歌单", description: "尝试歌单名、主题或歌手名。", symbol: "music.note.list")
            } else {
                ScrollView { MacPlaylistGrid(playlists: search.playlistResults, open: open).padding(26) }
            }
        }
    }
}
