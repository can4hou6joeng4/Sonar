import SwiftUI

struct MacDiscoveryView: View {
    let model: MacAppModel
    let discovery: DiscoveryViewModel
    let open: (MacCatalogDestination) -> Void
    private let source: MusicSource = .tx

    private var state: DiscoveryPageState { discovery.state(for: source) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("发现音乐").font(.largeTitle.bold())
                        Text("在熟悉之外，遇见新的声音。") .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { Task { await discovery.refresh(source) } } label: { Label("刷新", systemImage: "arrow.clockwise") }
                        .disabled(state.isLoading)
                }
                HStack {
                    Text("QQ 音乐歌单").foregroundStyle(.secondary)
                    Spacer()
                    if source.playlistCategories.count > 1 {
                        Picker("分类", selection: Binding(get: { discovery.selectedCategory(for: source).id }, set: { id in
                            if let category = source.playlistCategories.first(where: { $0.id == id }) {
                                Task { await discovery.selectCategory(category, for: source) }
                            }
                        })) {
                            ForEach(source.playlistCategories) { Text($0.name).tag($0.id) }
                        }.frame(width: 130)
                    }
                }
                if let error = state.errorMessage { MacInlineError(message: error) { Task { await discovery.refresh(source) } } }
                if state.isLoading {
                    ProgressView("正在发现好音乐…").frame(maxWidth: .infinity).padding(80)
                } else if state.items.isEmpty {
                    MacEmptyState(title: "暂无推荐歌单", description: "稍后刷新，或前往搜索找到喜欢的音乐。", symbol: "square.grid.2x2")
                        .frame(height: 240)
                } else {
                    MacPlaylistGrid(playlists: state.items, open: open)
                    if let error = state.loadMoreError {
                        MacInlineError(message: error) { Task { await discovery.loadMore(for: source) } }
                    }
                    if state.hasMore {
                        HStack {
                            Spacer()
                            Button(state.isLoadingMore ? "正在载入…" : "更多歌单") { Task { await discovery.loadMore(for: source) } }
                                .disabled(state.isLoadingMore)
                            Spacer()
                        }
                    }
                }
            }.padding(28)
        }.task(id: source) { await discovery.loadInitial(for: source) }
    }
}

struct MacPlaylistGrid: View {
    let playlists: [PlaylistSummary]
    let open: (MacCatalogDestination) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 22)], alignment: .leading, spacing: 26) {
            ForEach(playlists, id: \.key) { playlist in
                Button { open(.playlist(playlist)) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        MacArtworkView(url: playlist.img, size: 160, radius: 14)
                        Text(playlist.name).fontWeight(.medium).lineLimit(2).frame(height: 36, alignment: .topLeading)
                        Text(playlist.author.isEmpty ? playlist.source.displayName : playlist.author)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }.frame(width: 160, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
            }
        }
    }
}
