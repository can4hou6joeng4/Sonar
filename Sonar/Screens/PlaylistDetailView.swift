import SwiftData
import SwiftUI
import UIKit

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
    @Environment(\.m3Scheme) private var scheme
    @Environment(\.shellSafeAreaInsets) private var safeAreaInsets
    @Environment(PlaybackService.self) private var playbackService
    @Environment(ToastCenter.self) private var toastCenter

    @State private var selectedTrackForPlaylist: Track?
    @State private var selectedEntry: Entry?
    @State private var showingRename = false
    @State private var showingDelete = false
    @State private var renameText = ""
    @State private var errorMessage: String?
    @State private var navIsSolid = false

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
    private var tracks: [Track] { entries.map(\.track) }
    private var entries: [Entry] {
        if let playlist {
            return playlist.items.sorted { $0.sortIndex < $1.sortIndex }.enumerated().compactMap { index, item in
                guard let track = item.track.track else { return nil }
                return Entry(id: track.musicID, track: track, playlistIndex: index)
            }
        }
        return fallbackTracks.enumerated().map { Entry(id: $0.element.musicID, track: $0.element, playlistIndex: nil) }
    }
    var body: some View {
        ZStack(alignment: .top) {
            ScrollView {
                VStack(spacing: 0) {
                    hero
                    trackList.offset(y: -12)
                }
                .background {
                    NCMScrollThresholdObserver(threshold: 120) { navIsSolid = $0 }
                }
            }
            .scrollIndicators(.hidden)
            navigationBar
        }
        .background(scheme.appSurface.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .ignoresSafeArea(edges: .top)
        .navigationBarBackButtonHidden(true)
        .ncmEdgeSwipeBack()
        .sheet(item: $selectedTrackForPlaylist) { track in
            AddToPlaylistSheet(track: track)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog("歌曲操作", isPresented: Binding(
            get: { selectedEntry != nil },
            set: { if !$0 { selectedEntry = nil } }
        )) {
            Button("加入歌单", systemImage: "text.badge.plus") {
                selectedTrackForPlaylist = selectedEntry?.track
                selectedEntry = nil
            }
            if let entry = selectedEntry, let playlist, !playlist.isSystem, entry.playlistIndex != nil {
                Button("移出歌单", systemImage: "text.badge.minus", role: .destructive) {
                    remove(entry, from: playlist)
                }
            }
            Button("取消", role: .cancel) { selectedEntry = nil }
        }
        .alert("重命名歌单", isPresented: $showingRename) {
            TextField("歌单名称", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("保存", action: renamePlaylist)
        }
        .confirmationDialog("删除「\(title)」？", isPresented: $showingDelete, titleVisibility: .visible) {
            Button("删除歌单", role: .destructive, action: deletePlaylist)
            Button("取消", role: .cancel) {}
        } message: {
            Text("曲目仍会保留在本地曲库中。")
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

    private var hero: some View {
        GeometryReader { proxy in
            ZStack {
                PlayerArtwork(track: tracks.first, size: max(proxy.size.width, proxy.size.height) + 120, cornerRadius: 0)
                    .blur(radius: 40)
                    .saturation(1.5)
                    .scaleEffect(1.25)
                LinearGradient(
                    colors: [.black.opacity(0.46), .black.opacity(0.32), .black.opacity(0.50)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                HStack(alignment: .center, spacing: 14) {
                    PlayerArtwork(track: tracks.first, size: 120, cornerRadius: 8)
                        .shadow(color: .black.opacity(0.35), radius: 9, y: 6)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Text(playlist == nil ? fallbackSubtitle : "歌单 · \(tracks.count) 首")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.76))
                            .lineLimit(1)
                        if !fallbackDescription.isEmpty {
                            Text(fallbackDescription)
                                .font(.system(size: 12))
                                .foregroundStyle(.white.opacity(0.72))
                                .lineLimit(1)
                        }
                        Button {
                            if let playlist, !playlist.isSystem {
                                renameText = playlist.name
                                showingRename = true
                            } else {
                                playShuffled()
                            }
                        } label: {
                            Label(playlist == nil || playlist?.isSystem == true ? "随机播放" : "编辑歌单", systemImage: playlist == nil || playlist?.isSystem == true ? "shuffle" : "pencil")
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 12)
                                .frame(height: 30)
                                .overlay(Capsule().stroke(.white.opacity(0.45), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
                .padding(.top, safeAreaInsets.top + 60)
                .padding(.bottom, 24)
            }
            .clipped()
        }
        .frame(height: safeAreaInsets.top + 244)
    }

    private var navigationBar: some View {
        HStack(spacing: 0) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 19, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("返回")
            .accessibilityIdentifier("playlist-detail-back")
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)
                .opacity(navIsSolid ? 1 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let playlist, !playlist.isSystem {
                Menu {
                    Button("重命名", systemImage: "pencil") {
                        renameText = playlist.name
                        showingRename = true
                    }
                    Button("删除歌单", systemImage: "trash", role: .destructive) { showingDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 19, weight: .medium))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("更多")
            } else {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .foregroundStyle(navIsSolid ? scheme.onSurface : Color.white)
        .padding(.horizontal, 4)
        .padding(.top, safeAreaInsets.top)
        .background(navIsSolid ? scheme.appSurface : Color.clear)
        .animation(.easeOut(duration: 0.18), value: navIsSolid)
    }

    private var trackList: some View {
        LazyVStack(spacing: 0) {
            Button {
                guard !tracks.isEmpty else { return }
                Task { await playbackService.replaceQueue(tracks) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(scheme.primary)
                    Text("播放全部")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(scheme.onSurface)
                    Text("(\(tracks.count))")
                        .font(.system(size: 12))
                        .foregroundStyle(scheme.onSurfaceVariant)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
                .frame(height: 50)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(tracks.isEmpty)
            .accessibilityIdentifier("playlist-play-all")

            if entries.isEmpty {
                ContentUnavailableView("这个歌单还没有曲目", systemImage: "music.note.list")
                    .frame(minHeight: 260)
            } else {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    SongRow(
                        track: entry.track,
                        leading: .index(index + 1),
                        trailing: .more,
                        showAlbum: false,
                        showDivider: index < entries.count - 1,
                        isCurrent: playbackService.queue.current?.musicID == entry.track.musicID,
                        isPlaying: playbackService.state == .playing,
                        onPlay: { Task { await playbackService.replaceQueue(tracks, startingAt: index) } },
                        onAction: { selectedEntry = entry }
                    )
                }
            }
            Color.clear.frame(height: 146)
        }
        .background(scheme.appSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func playShuffled() {
        let shuffled = tracks.shuffled()
        guard !shuffled.isEmpty else { return }
        Task { await playbackService.replaceQueue(shuffled) }
        toastCenter.show("随机播放")
    }

    private func remove(_ entry: Entry, from playlist: Playlist) {
        guard let index = entry.playlistIndex else { return }
        do {
            try LibraryStore(context: modelContext).removeItem(at: index, from: playlist)
            selectedEntry = nil
            toastCenter.show("已移出歌单")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func renamePlaylist() {
        guard let playlist else { return }
        do {
            try LibraryStore(context: modelContext).rename(playlist, to: renameText)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deletePlaylist() {
        guard let playlist else { return }
        do {
            try LibraryStore(context: modelContext).delete(playlist)
            FavoritePlaylistRegistry().unregister(playlistID: playlist.id)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct NCMScrollThresholdObserver: UIViewRepresentable {
    let threshold: CGFloat
    let onChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(threshold: threshold, onChange: onChange)
    }

    func makeUIView(context: Context) -> NCMScrollThresholdProbeView {
        let view = NCMScrollThresholdProbeView()
        view.onAttach = { scrollView in context.coordinator.attach(to: scrollView) }
        return view
    }

    func updateUIView(_ uiView: NCMScrollThresholdProbeView, context: Context) {
        context.coordinator.update(threshold: threshold, onChange: onChange)
        uiView.findScrollView()
    }

    static func dismantleUIView(_ uiView: NCMScrollThresholdProbeView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject {
        private weak var scrollView: UIScrollView?
        private var observation: NSKeyValueObservation?
        private var lastValue: Bool?
        private var threshold: CGFloat
        private var onChange: (Bool) -> Void

        init(threshold: CGFloat, onChange: @escaping (Bool) -> Void) {
            self.threshold = threshold
            self.onChange = onChange
        }

        func attach(to scrollView: UIScrollView) {
            guard self.scrollView !== scrollView else { return }
            detach()
            self.scrollView = scrollView
            observation = scrollView.observe(\.contentOffset, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.publish() }
            }
        }

        func update(threshold: CGFloat, onChange: @escaping (Bool) -> Void) {
            self.threshold = threshold
            self.onChange = onChange
            publish()
        }

        func detach() {
            observation?.invalidate()
            observation = nil
            scrollView = nil
            lastValue = nil
        }

        private func publish() {
            guard let scrollView else { return }
            let offset = scrollView.contentOffset.y + scrollView.adjustedContentInset.top
            let value = offset > threshold
            guard value != lastValue else { return }
            lastValue = value
            onChange(value)
        }
    }
}

@MainActor
final class NCMScrollThresholdProbeView: UIView {
    var onAttach: ((UIScrollView) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        findScrollView()
    }

    func findScrollView() {
        var candidate = superview
        while let view = candidate {
            if let scrollView = view as? UIScrollView {
                onAttach?(scrollView)
                return
            }
            candidate = view.superview
        }
        DispatchQueue.main.async { [weak self] in self?.findScrollViewIfAttached() }
    }

    private func findScrollViewIfAttached() {
        guard window != nil else { return }
        var candidate = superview
        while let view = candidate {
            if let scrollView = view as? UIScrollView {
                onAttach?(scrollView)
                return
            }
            candidate = view.superview
        }
    }
}
