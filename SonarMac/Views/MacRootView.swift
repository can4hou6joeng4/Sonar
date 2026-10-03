import SwiftUI

enum MacSidebarDestination: String, CaseIterable, Identifiable {
    case home, discover, search, favorites, recent
    var id: String { rawValue }
    var title: String {
        switch self {
        case .home: "现在就听"
        case .discover: "发现音乐"
        case .search: "搜索"
        case .favorites: "个人歌单"
        case .recent: "最近播放"
        }
    }
    var symbol: String {
        switch self {
        case .home: "play.circle"
        case .discover: "square.grid.2x2"
        case .search: "magnifyingglass"
        case .favorites: "heart"
        case .recent: "clock"
        }
    }
}

enum MacCatalogDestination {
    case artist(ArtistSummary), album(AlbumSummary), playlist(PlaylistSummary)
}

struct MacRootView: View {
    let model: MacAppModel
    @SceneStorage("macSidebarSelection") private var selectedRaw = MacSidebarDestination.home.rawValue
    @SceneStorage("macInspectorVisible") private var showsInspector = false
    @State private var catalogPath: [MacCatalogDestination] = []
    @State private var searchFocusRequest = 0
    @State private var search: SearchViewModel
    @State private var discovery: DiscoveryViewModel
    @AppStorage("macAppearance") private var appearance = "system"

    init(model: MacAppModel) {
        self.model = model
        _search = State(initialValue: SearchViewModel(runtime: model.runtime))
        _discovery = State(initialValue: DiscoveryViewModel(runtime: model.runtime))
    }

    private var destination: MacSidebarDestination { MacSidebarDestination(rawValue: selectedRaw) ?? .home }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 175, ideal: 195, max: 245)
        } detail: {
            VStack(spacing: 0) {
                detail.frame(maxWidth: .infinity, maxHeight: .infinity)
                if case .failed(let message) = model.playback.state {
                    MacInlineError(message: message) { Task { await model.playback.retryCurrent() } }
                        .padding(12)
                }
                if let notice = model.notice {
                    HStack {
                        Text(notice).font(.callout)
                        Spacer()
                        Button { model.notice = nil } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).help("关闭提示")
                    }.padding(12).background(.regularMaterial)
                }
            }
            .navigationTitle(destination.title)
            .toolbar {
                ToolbarItem(placement: .navigation) {
                    if !catalogPath.isEmpty {
                        Button { catalogPath.removeLast() } label: { Label("返回", systemImage: "chevron.left") }
                            .keyboardShortcut("[", modifiers: .command)
                    }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        selectedRaw = MacSidebarDestination.search.rawValue
                        catalogPath = []
                        searchFocusRequest += 1
                    } label: { Label("搜索音乐", systemImage: "magnifyingglass") }
                    .keyboardShortcut("f", modifiers: .command)
                    Button { model.showNotch() } label: { Label("显示刘海播放器", systemImage: "macbook") }
                    Button { showsInspector.toggle() } label: { Label("队列与歌词", systemImage: "sidebar.right") }
                        .keyboardShortcut("i", modifiers: [.command, .option])
                }
            }
            .inspector(isPresented: $showsInspector) {
                MacPlayerInspector(model: model)
                    .inspectorColumnWidth(min: 260, ideal: 310, max: 380)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { MacTransportBar(model: model) }
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .frame(minWidth: 900, minHeight: 620)
        .onChange(of: selectedRaw) { _, _ in catalogPath = [] }
        .alert("Sonar", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("好") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private var sidebar: some View {
        List(selection: Binding<String?>(get: { selectedRaw }, set: { if let value = $0 { selectedRaw = value } })) {
            Section("Sonar") {
                ForEach([MacSidebarDestination.home, .discover, .search]) { item in
                    Label(item.title, systemImage: item.symbol).tag(item.rawValue)
                }
            }
            Section("资料库") {
                ForEach([MacSidebarDestination.favorites, .recent]) { item in
                    Label(item.title, systemImage: item.symbol).tag(item.rawValue)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Image(systemName: "waveform").foregroundStyle(.tint)
                Text("SONAR").font(.caption.weight(.semibold)).tracking(3)
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }.buttonStyle(.plain).help("设置")
            }.padding(18)
        }
    }

    @ViewBuilder private var detail: some View {
        if let item = catalogPath.last {
            switch item {
            case .artist(let artist): MacArtistDetailView(model: model, artist: artist, open: open).id(artist.stableID)
            case .album(let album): MacAlbumDetailView(model: model, album: album).id(album.stableID)
            case .playlist(let playlist): MacPlaylistDetailView(model: model, playlist: playlist).id(playlist.key)
            }
        } else {
            switch destination {
            case .home: MacHomeView(model: model, search: { selectedRaw = "search" }, openFavorites: { selectedRaw = "favorites" })
            case .discover: MacDiscoveryView(model: model, discovery: discovery, open: open)
            case .search: MacSearchView(model: model, search: search, focusRequest: searchFocusRequest, open: open)
            case .favorites: libraryPage(title: "个人歌单", description: "把喜欢的声音，留在这里。", tracks: model.libraryTracks, removable: true)
            case .recent: libraryPage(title: "最近播放", description: "回到上一次心动的旋律。", tracks: model.recentTracks, removable: false)
            }
        }
    }

    private func open(_ item: MacCatalogDestination) { catalogPath.append(item) }

    private func libraryPage(title: String, description: String, tracks: [Track], removable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(title).font(.largeTitle.bold())
                    Text("\(description)  \(tracks.count) 首歌曲").foregroundStyle(.secondary)
                }
                Spacer()
                if removable {
                    Menu {
                        Button("导入歌单…") { model.importBackup() }
                        Button("导出歌单…") { model.exportBackup() }
                    } label: { Label("歌单备份", systemImage: "ellipsis") }
                }
                Button("全部播放", systemImage: "play.fill") {
                    Task {
                        if removable { await model.playFavorites() }
                        else { await model.play(tracks) }
                    }
                }
                    .buttonStyle(.borderedProminent).disabled(tracks.isEmpty)
            }.padding(26)
            MacTrackTable(model: model, tracks: tracks, allowsRemoval: removable)
        }
    }
}
