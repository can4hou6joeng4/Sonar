import SwiftData
import SwiftUI

struct PlaylistDetailView: View {
    private struct Entry: Identifiable {
        let id: String
        let track: Track
        let playlistIndex: Int?
    }

    private let playlist: Playlist?
    private let fallbackTitle: String
    private let fallbackSubtitle: String
    private let fallbackDescription: String
    private let fallbackTracks: [Track]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.artworkService) private var artworkService
    @Environment(\.m3Scheme) private var globalScheme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.shellSafeAreaInsets) private var shellSafeAreaInsets
    @Environment(\.sonarReduceMotion) private var reduceMotion
    @Environment(PlaybackService.self) private var playbackService
    @Environment(ToastCenter.self) private var toastCenter

    @State private var localScheme: M3Scheme?
    @State private var selectedTrackForPlaylist: Track?
    @State private var showingRename = false
    @State private var showingDelete = false
    @State private var showingDescription = false
    @State private var renameText = ""
    @State private var errorMessage: String?

    init(playlist: Playlist) {
        self.playlist = playlist
        fallbackTitle = playlist.name
        fallbackSubtitle = "我的歌单"
        fallbackDescription = ""
        fallbackTracks = []
    }

    init(title: String, subtitle: String, description: String, tracks: [Track]) {
        playlist = nil
        fallbackTitle = title
        fallbackSubtitle = subtitle
        fallbackDescription = description
        fallbackTracks = tracks
    }

    private var title: String { playlist?.name ?? fallbackTitle }

    private var entries: [Entry] {
        if let playlist {
            return playlist.items.sorted { $0.sortIndex < $1.sortIndex }.enumerated().compactMap { index, item -> Entry? in
                guard let track = item.track.track else { return nil }
                return Entry(id: String(describing: item.persistentModelID), track: track, playlistIndex: index)
            }
        }
        return fallbackTracks.enumerated().map { index, track in
            Entry(id: "\(track.musicID)-\(index)", track: track, playlistIndex: nil)
        }
    }

    private var tracks: [Track] { entries.map(\.track) }

    private var subtitle: String {
        let duration = tracks.compactMap(\.durationSeconds).reduce(0, +)
        let minutes = Int(duration / 60)
        let prefix = playlist == nil ? fallbackSubtitle : "我的歌单"
        return "\(prefix) · \(tracks.count) 首 · 约 \(minutes) 分钟"
    }

    private var detailDescription: String {
        if !fallbackDescription.isEmpty { return fallbackDescription }
        return playlist == nil ? "" : "收藏声音，也收藏它出现时的那段时间。"
    }

    var body: some View {
        let scheme = localScheme ?? globalScheme

        List {
            hero(scheme: scheme)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(scheme.surface)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(scheme.onSurface)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(scheme.onSurfaceVariant)
                    .padding(.top, 8)
                if !detailDescription.isEmpty {
                    Text(detailDescription)
                        .font(.system(size: 12.5))
                        .foregroundStyle(scheme.onSurfaceVariant.opacity(0.9))
                        .lineSpacing(2)
                        .lineLimit(2)
                        .frame(height: 40, alignment: .topLeading)
                        .padding(.top, 10)
                        .onLongPressGesture { showingDescription = true }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(scheme.surface)

            PlaylistDetailActions(
                isLoading: false,
                isFavoriteInProgress: false,
                isFavorite: false,
                showFavorite: false,
                onPlayAll: {
                    guard !tracks.isEmpty else { return }
                    Task { await playbackService.replaceQueue(tracks) }
                },
                onFavorite: {}
            )
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(scheme.surface)

            Text("歌曲  \(entries.count)")
                .font(.title3.weight(.bold))
                .foregroundStyle(scheme.onSurface)
                .frame(maxWidth: 900, minHeight: 24, alignment: .leading)
                .padding(.init(top: 16, leading: 16, bottom: 8, trailing: 16))
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(scheme.surface)
                .accessibilityIdentifier("playlist-track-count")

            if entries.isEmpty {
                ContentUnavailableView("这个歌单还没有曲目", systemImage: "music.note.list")
                    .listRowBackground(scheme.surface)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.id) { queueIndex, entry in
                    detailRow(entry: entry, queueIndex: queueIndex, scheme: scheme)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(scheme.surface)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(scheme.surface.ignoresSafeArea())
        .environment(\.m3Scheme, scheme)
        .toolbar(.hidden, for: .navigationBar)
        .ignoresSafeArea(edges: .top)
        .animation(
            AppMotion.emphasized(duration: AppMotion.long, reduceMotion: reduceMotion),
            value: localScheme?.seedHex
        )
        .task(id: tracks.first?.musicID) { await updateLocalScheme() }
        .sheet(item: $selectedTrackForPlaylist) { track in
            AddToPlaylistSheet(track: track)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .alert("歌单简介", isPresented: $showingDescription) {
            Button("好", role: .cancel) {}
        } message: {
            Text(detailDescription)
        }
        .alert("重命名歌单", isPresented: $showingRename) {
            TextField("歌单名称", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("保存") {
                guard let playlist else { return }
                perform { try LibraryStore(context: modelContext).rename(playlist, to: renameText) }
            }
        }
        .confirmationDialog("确定删除“\(title)”？", isPresented: $showingDelete, titleVisibility: .visible) {
            Button("删除歌单", role: .destructive) {
                guard let playlist else { return }
                perform {
                    try LibraryStore(context: modelContext).delete(playlist)
                    dismiss()
                }
            }
        } message: {
            Text("曲目本身不会被删除。")
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private func hero(scheme: M3Scheme) -> some View {
        GeometryReader { proxy in
            ZStack {
                PlayerArtwork(track: tracks.first, size: max(proxy.size.width, proxy.size.height))
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                LinearGradient(
                    colors: [.black.opacity(0.54), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.68),
                        .init(color: scheme.surface.opacity(0.18), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                VStack {
                    HStack(spacing: 4) {
                        heroButton(systemImage: "chevron.left", label: "返回") { dismiss() }
                        Text(playlist == nil ? "歌单详情" : title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.52), radius: 8)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Menu {
                            Button("播放全部", systemImage: "play.fill") {
                                guard !tracks.isEmpty else { return }
                                Task { await playbackService.replaceQueue(tracks) }
                            }
                            if let playlist, !playlist.isSystem {
                                Button("重命名", systemImage: "pencil") {
                                    renameText = playlist.name
                                    showingRename = true
                                }
                                Button("删除歌单", systemImage: "trash", role: .destructive) {
                                    showingDelete = true
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(.black.opacity(0.19), in: Circle())
                        }
                        .accessibilityLabel("更多")
                        .accessibilityIdentifier("playlist-detail-more")
                    }
                    .padding(.horizontal, 12)
                    // List 忽略顶部安全区后，行内 GeometryReader 读到的 inset 会归零。
                    // 使用 Shell 的真实 inset，避免沉浸头图顶栏被状态栏裁掉。
                    .padding(.top, shellSafeAreaInsets.top + 4)
                    Spacer()
                }
            }
        }
        .frame(height: min(max(UIScreen.main.bounds.height * 0.4, 320), 460))
        .clipped()
    }

    private func heroButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.19), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier("playlist-detail-back")
    }

    private func detailRow(entry: Entry, queueIndex: Int, scheme: M3Scheme) -> some View {
        SongRow(
            track: entry.track,
            isCurrent: playbackService.queue.current?.musicID == entry.track.musicID,
            isPlaying: playbackService.state == .playing,
            onPlay: { Task { await playbackService.replaceQueue(tracks, startingAt: queueIndex) } },
            onAction: { selectedTrackForPlaylist = entry.track }
        )
        .padding(.horizontal, 14)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if let playlist, !playlist.isSystem, let index = entry.playlistIndex {
                Button("移出歌单", systemImage: "text.badge.minus", role: .destructive) {
                    perform { try LibraryStore(context: modelContext).removeItem(at: index, from: playlist) }
                    toastCenter.show("已移出歌单")
                }
            }
            Button("歌单", systemImage: "text.badge.plus") {
                selectedTrackForPlaylist = entry.track
            }
            .tint(scheme.secondary)
        }
    }

    private func updateLocalScheme() async {
        guard let track = tracks.first else {
            localScheme = nil
            return
        }
        let cachedHex = playlist?.items
            .sorted { $0.sortIndex < $1.sortIndex }
            .first?.track.accentHex
        let accentHex: String?
        if let cachedHex {
            accentHex = cachedHex
        } else if let artworkService {
            accentHex = try? await artworkService.accentHex(for: track)
        } else {
            accentHex = nil
        }
        guard !Task.isCancelled, let accentHex else { return }
        localScheme = .tonalSpot(seedHex: accentHex, dark: colorScheme == .dark)
    }

    private func perform(_ operation: () throws -> Void) {
        do { try operation() } catch { errorMessage = error.localizedDescription }
    }
}
