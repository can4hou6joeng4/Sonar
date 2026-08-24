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

struct QueueSheet: View {
    @Environment(\.playerPalette) private var palette

    var body: some View {
        QueueFace()
            .padding(.top, 8)
            .background(palette.queueBackground.ignoresSafeArea())
    }
}

struct QueueFace: View {
    @Environment(PlaybackService.self) private var playbackService
    @Environment(ToastCenter.self) private var toastCenter
    @Environment(\.m3Scheme) private var scheme
    @State private var drag: DragState?

    var body: some View {
        VStack(spacing: 0) {
            header
            if playbackService.queue.tracks.isEmpty {
                emptyState
            } else {
                queueList
            }
        }
        .foregroundStyle(NCMDesignTokens.Player.primaryInk)
        .accessibilityIdentifier("playback-queue-list")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("当前播放 (\(playbackService.queue.tracks.count))")
                .font(.system(size: 16, weight: .bold))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: cycleMode) {
                Label(playbackService.playbackMode.title, systemImage: playbackService.playbackMode.systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .labelStyle(.titleAndIcon)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(NCMDesignTokens.Player.secondaryInk)
            .accessibilityIdentifier("queue-playback-mode")

            Button {
                playbackService.clearUpcoming()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 30, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(NCMDesignTokens.Player.secondaryInk)
            .disabled(playbackService.queue.currentIndex == nil)
            .accessibilityLabel("清空待播")
            .accessibilityIdentifier("queue-clear-upcoming")
        }
        .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
        .frame(height: 44)
    }

    private var queueList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(playbackService.queue.tracks.enumerated()), id: \.offset) { index, track in
                        queueRow(track: track, index: index)
                            .id(index)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .mask(queueFade)
            .coordinateSpace(name: "ncm-player-queue")
            .onAppear {
                guard let index = playbackService.queue.currentIndex else { return }
                Task { @MainActor in
                    await Task.yield()
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
    }

    private func queueRow(track: Track, index: Int) -> some View {
        let isCurrent = playbackService.queue.currentIndex == index
        let destination = drag.map {
            QueueDragMetrics.destination(
                from: $0.source,
                translation: $0.translation,
                count: playbackService.queue.tracks.count
            )
        } ?? index
        let offset = drag.map {
            QueueDragMetrics.rowOffset(
                index: index,
                source: $0.source,
                destination: destination,
                translation: $0.translation
            )
        } ?? 0

        return HStack(spacing: 12) {
            Button {
                Task { await playbackService.selectQueueItem(at: index) }
            } label: {
                HStack(spacing: 12) {
                    Group {
                        if isCurrent {
                            PlayingEqualizer(
                                isAnimating: playbackService.state == .playing,
                                color: scheme.primary
                            )
                        } else {
                            Color.clear.frame(width: 9, height: 11)
                        }
                    }
                    .frame(width: 11)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(track.title)
                            .font(.system(size: NCMDesignTokens.Typography.queueTitle))
                            .foregroundStyle(isCurrent ? scheme.primary : NCMDesignTokens.Player.primaryInk)
                            .lineLimit(1)
                        Text("- \(track.artist)")
                            .font(.system(size: NCMDesignTokens.Typography.queueSubtitle))
                            .foregroundStyle(NCMDesignTokens.Player.secondaryInk)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(track.title)，\(track.artist)")
            .accessibilityIdentifier("playback-queue-row-\(index)")
            .accessibilityAddTraits(isCurrent ? .isSelected : [])

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(NCMDesignTokens.Player.tertiaryInk)
                .frame(width: 30, height: 44)
                .contentShape(Rectangle())
                .gesture(reorderGesture(index: index))
                .accessibilityLabel("拖动排序")

            Button {
                Task { await playbackService.removeQueueItem(at: index) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 30, height: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(NCMDesignTokens.Player.tertiaryInk)
            .accessibilityLabel("移除 \(track.title)")
        }
        .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
        .frame(height: QueueDragMetrics.rowHeight)
        .background(.white.opacity(drag?.source == index ? 0.10 : 0))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.10))
                .frame(height: 0.5)
                .padding(.horizontal, NCMDesignTokens.Layout.horizontalPadding)
        }
        .offset(y: offset)
        .zIndex(drag?.source == index ? 2 : 1)
        .animation(
            drag?.source == index ? nil : .timingCurve(0.2, 0, 0, 1, duration: AppMotion.queueReorder),
            value: offset
        )
    }

    private func reorderGesture(index: Int) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .named("ncm-player-queue"))
            .onChanged { value in
                if drag == nil { drag = DragState(source: index, translation: 0) }
                guard drag?.source == index else { return }
                drag?.translation = value.translation.height
            }
            .onEnded { value in
                guard let drag, drag.source == index else {
                    self.drag = nil
                    return
                }
                let destination = QueueDragMetrics.destination(
                    from: index,
                    translation: value.translation.height,
                    count: playbackService.queue.tracks.count
                )
                self.drag = nil
                guard destination != index else { return }
                playbackService.moveQueueItems(
                    fromOffsets: IndexSet(integer: index),
                    toOffset: QueueDragMetrics.insertionOffset(from: index, to: destination)
                )
            }
    }

    private var queueFade: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.05),
                .init(color: .black, location: 0.94),
                .init(color: .clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note.list")
                .font(.system(size: 34, weight: .regular))
            Text("播放列表为空")
                .font(.system(size: 14, weight: .medium))
        }
        .foregroundStyle(NCMDesignTokens.Player.tertiaryInk)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func cycleMode() {
        let mode = playbackService.playbackMode.next
        playbackService.setPlaybackMode(mode)
        toastCenter.show(mode.title)
    }
}

private extension QueueFace {
    struct DragState {
        let source: Int
        var translation: CGFloat
    }
}
