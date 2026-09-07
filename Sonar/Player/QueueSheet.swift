import SwiftUI

enum QueueDragMetrics {
    static let rowHeight = NCMDesignTokens.Layout.queueRowHeight

    static func destination(from index: Int, translation: CGFloat, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index + Int((translation / rowHeight).rounded()), 0), count - 1)
    }

    static func insertionOffset(from source: Int, to destination: Int) -> Int {
        source < destination ? destination + 1 : destination
    }

    static func rowOffset(index: Int, source: Int, destination: Int, translation: CGFloat) -> CGFloat {
        if index == source { return translation }
        if source < destination, index > source, index <= destination { return -rowHeight }
        if source > destination, index >= destination, index < source { return rowHeight }
        return 0
    }
}

struct QueueDisplayItem: Identifiable {
    let index: Int
    let track: Track

    var id: Int { index }
}

struct QueueProjection {
    let current: QueueDisplayItem?
    let upcoming: [QueueDisplayItem]

    init(tracks: [Track], currentIndex: Int?) {
        let items = tracks.enumerated().map { QueueDisplayItem(index: $0.offset, track: $0.element) }
        guard let currentIndex, items.indices.contains(currentIndex) else {
            current = nil
            upcoming = items
            return
        }
        current = items[currentIndex]
        upcoming = Array(items.dropFirst(currentIndex + 1))
    }
}

struct QueueSheet: View {
    @Environment(\.playerPalette) private var palette

    var body: some View {
        QueueFace(presentation: .sheet)
            .padding(.top, 8)
            .background(palette.queueBackground.ignoresSafeArea())
    }
}

enum QueuePresentationStyle {
    case sheet
    case player

    var hasExternalTransportBar: Bool {
        self == .player
    }

    func title(trackCount: Int) -> String {
        let count = max(trackCount, 0)
        switch self {
        case .sheet:
            return "待播放 (\(count))"
        case .player:
            return "待播放 \(count) 首"
        }
    }

    func accessibilityCount(trackCount: Int) -> String {
        "\(max(trackCount, 0)) 首歌曲"
    }
}

enum QueueCurrentItemPresentation {
    static func accessibilityStatus(for state: PlaybackService.State) -> String {
        guard case let .failed(message) = state else {
            return PlaybackStatusPresentation.text(for: state)
        }
        let reason = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return reason.isEmpty ? "播放失败" : "播放失败：\(reason)"
    }

    static func playbackControlLabel(
        for state: PlaybackService.State,
        playbackRequested: Bool
    ) -> String {
        switch state {
        case .playing:
            return "暂停"
        case .loading:
            return playbackRequested ? "暂停加载" : "播放"
        case .failed:
            return "重试播放"
        case .idle, .paused:
            return "播放"
        }
    }

    static func playbackControlIcon(
        for state: PlaybackService.State,
        playbackRequested: Bool
    ) -> String {
        switch state {
        case .playing:
            return "pause.circle.fill"
        case .loading where playbackRequested:
            return "pause.circle.fill"
        case .failed:
            return "arrow.clockwise.circle.fill"
        case .idle, .loading, .paused:
            return "play.circle.fill"
        }
    }
}

struct QueueFace: View {
    let presentation: QueuePresentationStyle

    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.sonarReduceMotion) private var reduceMotion
    @State private var drag: DragState?

    private var projection: QueueProjection {
        QueueProjection(
            tracks: playbackService.queue.tracks,
            currentIndex: playbackService.queue.currentIndex
        )
    }

    private var hasClearableUpcoming: Bool {
        guard let currentIndex = playbackService.queue.currentIndex else { return false }
        return currentIndex < playbackService.queue.tracks.count - 1
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if playbackService.queue.tracks.isEmpty {
                emptyState
            } else {
                queueList
                if !presentation.hasExternalTransportBar {
                    modeFooter
                }
            }
        }
        .foregroundStyle(NCMDesignTokens.Player.primaryInk)
        .accessibilityIdentifier("playback-queue-list")
    }

    private var header: some View {
        HStack(spacing: 10) {
            if presentation == .player {
                Label(
                    presentation.title(trackCount: playbackService.queue.tracks.count),
                    systemImage: "music.note.list"
                )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(NCMDesignTokens.Player.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("queue-summary")
            } else {
                Text(presentation.title(trackCount: playbackService.queue.tracks.count))
                    .font(.headline)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                playbackService.clearUpcoming()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(NCMDesignTokens.Player.secondaryInk)
            .disabled(!hasClearableUpcoming)
            .accessibilityLabel("清空待播")
            .accessibilityIdentifier("queue-clear-upcoming")
        }
        .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
        .frame(height: presentation == .player ? 52 : 44)
    }

    private var modeFooter: some View {
        Button(action: cycleMode) {
            Label(playbackService.playbackMode.title, systemImage: playbackService.playbackMode.systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(NCMDesignTokens.Player.secondaryInk)
                .frame(maxWidth: .infinity, minHeight: 52)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(height: 0.5)
        }
        .accessibilityLabel("播放模式，\(playbackService.playbackMode.title)")
        .accessibilityHint("双击切换播放模式")
        .accessibilityIdentifier("queue-playback-mode")
    }

    private var queueList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let current = projection.current {
                    currentPlaybackContext(current)
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("接下来播放")
                        .font(.headline)
                    Text("\(projection.upcoming.count) 首")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(NCMDesignTokens.Player.secondaryInk)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
                .padding(.top, 16)
                .padding(.bottom, 8)
                .accessibilityElement(children: .combine)

                if projection.upcoming.isEmpty {
                    Text("接下来没有歌曲")
                        .font(.subheadline)
                        .foregroundStyle(NCMDesignTokens.Player.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 76)
                } else {
                    ForEach(Array(projection.upcoming.enumerated()), id: \.element.id) { position, item in
                        queueRow(
                            item: item,
                            displayPosition: position,
                            displayCount: projection.upcoming.count
                        )
                        .id(item.index)
                    }
                }
            }
        }
        .scrollIndicators(.visible)
        .coordinateSpace(name: "ncm-player-queue")
    }

    private func currentPlaybackContext(_ item: QueueDisplayItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                PlayerArtwork(track: item.track, size: 58, cornerRadius: 7)
                PlayingEqualizer(
                    isAnimating: playbackService.state == .playing,
                    color: .white
                )
                .padding(4)
                .background(.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 4))
            }
            .frame(width: 58, height: 58)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("当前播放")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NCMDesignTokens.Player.secondaryInk)
                Text(item.track.title)
                    .font(.headline)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.track.artist)
                    .font(.caption)
                    .foregroundStyle(NCMDesignTokens.Player.secondaryInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("当前播放，\(item.track.title)，\(item.track.artist)")
            .accessibilityValue(QueueCurrentItemPresentation.accessibilityStatus(for: playbackService.state))
            .accessibilityIdentifier("queue-current-track")

            if !presentation.hasExternalTransportBar {
                Button {
                    Task { await playbackService.togglePlayback() }
                } label: {
                    Image(
                        systemName: QueueCurrentItemPresentation.playbackControlIcon(
                            for: playbackService.state,
                            playbackRequested: playbackService.playbackRequested
                        )
                    )
                        .font(.system(size: 34, weight: .regular))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    QueueCurrentItemPresentation.playbackControlLabel(
                        for: playbackService.state,
                        playbackRequested: playbackService.playbackRequested
                    )
                )
                .accessibilityIdentifier("queue-current-play-pause")
            }

            Menu {
                Button("移出待播放", systemImage: "text.badge.minus", role: .destructive) {
                    Task { await playbackService.removeQueueItem(at: item.index) }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            .foregroundStyle(NCMDesignTokens.Player.secondaryInk)
            .accessibilityLabel("管理当前歌曲")
            .accessibilityIdentifier("queue-current-menu")
        }
        .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
        .padding(.vertical, 11)
        .frame(minHeight: 80)
        .dynamicTypeSize(.xSmall ... .accessibility3)
        .background(.white.opacity(0.045))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 0.5)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    private func queueRow(
        item: QueueDisplayItem,
        displayPosition: Int,
        displayCount: Int
    ) -> some View {
        let track = item.track
        let index = item.index
        let destination = drag.map {
            QueueDragMetrics.destination(
                from: $0.sourcePosition,
                translation: $0.translation,
                count: displayCount
            )
        } ?? displayPosition
        let offset = drag.map {
            QueueDragMetrics.rowOffset(
                index: displayPosition,
                source: $0.sourcePosition,
                destination: destination,
                translation: $0.translation
            )
        } ?? 0

        return HStack(spacing: 10) {
            Button {
                Task { await playbackService.selectQueueItem(at: index) }
            } label: {
                HStack(spacing: 10) {
                    PlayerArtwork(track: track, size: 44, cornerRadius: 6)
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title)
                            .font(.subheadline)
                            .foregroundStyle(NCMDesignTokens.Player.primaryInk)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(track.artist)
                            .font(.caption)
                            .foregroundStyle(NCMDesignTokens.Player.secondaryInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(track.title)，\(track.artist)")
            .accessibilityIdentifier("playback-queue-row-\(index)")

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(NCMDesignTokens.Player.tertiaryInk)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .gesture(reorderGesture(item: item, displayPosition: displayPosition))
                .accessibilityLabel("拖动排序")

            Menu {
                Button("移出待播放", systemImage: "text.badge.minus", role: .destructive) {
                    Task { await playbackService.removeQueueItem(at: index) }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            .foregroundStyle(NCMDesignTokens.Player.tertiaryInk)
            .accessibilityLabel("管理 \(track.title)")
        }
        .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
        .padding(.vertical, 5)
        .frame(minHeight: QueueDragMetrics.rowHeight)
        .background(.white.opacity(drag?.sourceIndex == index ? 0.10 : 0))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(height: 0.5)
                .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
        }
        .offset(y: offset)
        .zIndex(drag?.sourceIndex == index ? 2 : 1)
        .animation(
            drag?.sourceIndex == index || reduceMotion
                ? nil
                : .timingCurve(0.2, 0, 0, 1, duration: AppMotion.queueReorder),
            value: offset
        )
    }

    private func reorderGesture(item: QueueDisplayItem, displayPosition: Int) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("ncm-player-queue"))
            .onChanged { value in
                if drag == nil {
                    drag = DragState(
                        sourceIndex: item.index,
                        sourcePosition: displayPosition,
                        translation: 0
                    )
                }
                guard drag?.sourceIndex == item.index else { return }
                drag?.translation = value.translation.height
            }
            .onEnded { value in
                guard let drag, drag.sourceIndex == item.index else {
                    self.drag = nil
                    return
                }
                let destinationPosition = QueueDragMetrics.destination(
                    from: displayPosition,
                    translation: value.translation.height,
                    count: projection.upcoming.count
                )
                self.drag = nil
                guard destinationPosition != displayPosition,
                      projection.upcoming.indices.contains(destinationPosition)
                else { return }
                let destinationIndex = projection.upcoming[destinationPosition].index
                playbackService.moveQueueItems(
                    fromOffsets: IndexSet(integer: item.index),
                    toOffset: QueueDragMetrics.insertionOffset(from: item.index, to: destinationIndex)
                )
            }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note.list")
                .font(.system(size: 34, weight: .regular))
            Text("待播放为空")
                .font(.system(size: 14, weight: .medium))
        }
        .foregroundStyle(NCMDesignTokens.Player.tertiaryInk)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func cycleMode() {
        let mode = playbackService.playbackMode.next
        playbackService.setPlaybackMode(mode)
    }
}

private extension QueueFace {
    struct DragState {
        let sourceIndex: Int
        let sourcePosition: Int
        var translation: CGFloat
    }
}
