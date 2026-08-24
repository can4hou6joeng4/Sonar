import Observation
import SwiftUI
import UIKit

struct KaraokeLyricsView: View {
    let lyrics: KaraokeLyrics
    let errorMessage: String?
    let edgeFadeEnabled: Bool

    @Environment(PlaybackService.self) private var playbackService
    @Environment(\.sonarReduceMotion) private var reduceMotion
    @State private var state = KaraokeLyricsViewState()

    var body: some View {
        Group {
            if lyrics.lines.isEmpty {
                emptyState
            } else {
                lyricsContent
            }
        }
        .onAppear(perform: synchronizePlayback)
        .onChange(of: lyrics) { _, _ in
            state.reset()
            synchronizePlayback()
        }
        .onChange(of: playbackService.elapsed) { _, _ in synchronizePlayback() }
        .onChange(of: playbackService.state) { _, _ in synchronizePlayback() }
        .onChange(of: reduceMotion) { _, _ in synchronizePlayback() }
    }

    private var lyricsContent: some View {
        GeometryReader { geometry in
            ZStack {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .center, spacing: 0) {
                        Color.clear.frame(height: geometry.size.height * 0.40)
                        ForEach(lyrics.lines) { line in
                            measuredLine(line)
                        }
                        Color.clear.frame(height: geometry.size.height * 0.60)
                    }
                    .coordinateSpace(name: KaraokeCoordinateSpace.content)
                    .background {
                        KaraokeScrollBridge(
                            targetOffset: state.scrollOffset,
                            onMetrics: { offset, viewportHeight, contentHeight in
                                state.updateScrollMetrics(
                                    offset: offset,
                                    viewportHeight: viewportHeight,
                                    contentHeight: contentHeight
                                )
                            },
                            onUserScrollBegan: { state.userScrollBegan(at: .now) },
                            onUserScrollEnded: { state.userScrollEnded(at: .now) }
                        )
                    }
                    .onPreferenceChange(KaraokeLineFramesKey.self) { frames in
                        state.updateLineFrames(frames, at: .now)
                    }
                }
                .scrollDismissesKeyboard(.immediately)
                .mask {
                    KaraokeEdgeFadeMask(enabled: edgeFadeEnabled, height: geometry.size.height)
                }
                .overlay {
                    KaraokeFrameTicker(state: state)
                }
                .accessibilityIdentifier("karaoke-lyrics-list")

                if lyrics.isSynthesized {
                    Text("这首歌没有逐字歌词 · 已按字数合成")
                        .font(.system(size: 10.5))
                        .foregroundStyle(NCMDesignTokens.Player.tertiaryInk)
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 2)
                        .allowsHitTesting(false)
                }

                if state.userScrollLocked {
                    Button {
                        state.resumeFollowing(at: .now)
                    } label: {
                        Label("回到当前", systemImage: "play.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(NCMDesignTokens.Player.primaryInk)
                            .padding(.horizontal, 14)
                            .frame(height: 30)
                            .background(.white.opacity(0.16), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 8)
                    .accessibilityIdentifier("lyrics-return-current")
                }
            }
        }
    }

    private func measuredLine(_ line: KaraokeLine) -> some View {
        KaraokeMeasuredLine(index: line.id) {
            KaraokeLyricLineView(
                line: line,
                state: state,
                showTranslation: state.showTranslation,
                onSelect: { select(line) }
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "music.note")
                .font(.system(size: 34, weight: .regular))
            Text(errorMessage ?? "暂无歌词")
                .font(.system(size: 14, weight: .medium))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(NCMDesignTokens.Player.tertiaryInk)
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func synchronizePlayback() {
        state.receivePlayback(
            lyrics: lyrics,
            elapsed: playbackService.elapsed,
            duration: playbackService.duration,
            playbackState: playbackService.state,
            reduceMotion: reduceMotion,
            at: .now
        )
    }

    private func select(_ line: KaraokeLine) {
        state.selectLine(line.id, startMs: line.startMs, at: .now)
        Task { await playbackService.seek(to: Double(line.startMs) / 1_000) }
    }
}

@MainActor
@Observable
private final class KaraokeLyricsViewState {
    private static let scrollAnchor = 0.40
    private static let springStiffness = 210.0
    private static let springDamping = 27.0
    private static let waveStiffness = 200.0
    private static let waveDamping = 2 * sqrt(200.0) * 1.1

    var activeIndex: Int?
    var selectedIndex: Int?
    var showTranslation = true
    var blurSuppressed = false
    var scrollOffset: CGFloat = 0
    var waveOffsets: [Int: CGFloat] = [:]

    private var lyrics = KaraokeLyrics()
    private var anchorSeconds: TimeInterval = 0
    private var anchorDate = Date.now
    private var duration: TimeInterval = 0
    private var isPlaying = false
    private var isBuffering = false
    private var reduceMotion = false
    private var viewportHeight: CGFloat = 0
    private var contentHeight: CGFloat = 0
    private var lineFrames: [Int: CGRect] = [:]
    private var lastFrameDate: Date?
    private var spring = ScrollSpring()
    private var waves: [Int: WaveState] = [:]
    private var waveStartedAt: Date?
    private(set) var userScrollLocked = false
    private var unlockAt: Date?
    private var blurRestoreAt: Date?
    private var selectionClearAt: Date?
    private var translationAnchor: TranslationAnchor?

    var shouldTick: Bool {
        sweepIsRunning
            || spring.isRunning
            || !waves.isEmpty
            || unlockAt != nil
            || blurRestoreAt != nil
            || selectionClearAt != nil
            || translationAnchor != nil
    }

    var sweepIsRunning: Bool {
        isPlaying && !isBuffering && !reduceMotion
    }

    func reset() {
        activeIndex = nil
        selectedIndex = nil
        blurSuppressed = false
        scrollOffset = 0
        waveOffsets = [:]
        lineFrames = [:]
        lastFrameDate = nil
        spring = ScrollSpring()
        waves = [:]
        waveStartedAt = nil
        userScrollLocked = false
        unlockAt = nil
        blurRestoreAt = nil
        selectionClearAt = nil
        translationAnchor = nil
    }

    func receivePlayback(
        lyrics: KaraokeLyrics,
        elapsed: TimeInterval,
        duration: TimeInterval,
        playbackState: PlaybackService.State,
        reduceMotion: Bool,
        at date: Date
    ) {
        let expected = effectiveSeconds(at: date)
        let isDiscontinuous = abs(elapsed - expected) > 0.55
        self.lyrics = lyrics
        self.duration = duration
        self.reduceMotion = reduceMotion
        isPlaying = playbackState == .playing
        isBuffering = playbackState == .loading
        anchorSeconds = max(0, elapsed)
        anchorDate = date
        updateActiveIndex(at: elapsed, isSeek: isDiscontinuous, date: date)
    }

    func tick(at date: Date) {
        let delta = min(max(date.timeIntervalSince(lastFrameDate ?? date), 0), 0.05)
        lastFrameDate = date

        updateDeadlines(at: date)
        updateActiveIndex(at: effectiveSeconds(at: date), isSeek: false, date: date)
        stepScrollSpring(delta: delta)
        stepWaves(delta: delta, date: date)
    }

    func effectiveMilliseconds(at date: Date) -> Double {
        effectiveSeconds(at: date) * 1_000
    }

    func updateScrollMetrics(offset: CGFloat, viewportHeight: CGFloat, contentHeight: CGFloat) {
        self.viewportHeight = viewportHeight
        self.contentHeight = contentHeight
        if abs(scrollOffset - offset) > 0.1 {
            scrollOffset = max(0, offset)
        }
        if spring.isRunning {
            spring.position = scrollOffset
        }
        refreshRoughTargetIfPossible()
    }

    func updateLineFrames(_ frames: [Int: CGRect], at date: Date) {
        lineFrames = frames
        if let anchor = translationAnchor,
           let frame = frames[anchor.index],
           date <= anchor.expiresAt {
            let target = clampedOffset(frame.midY - anchor.screenY)
            scrollOffset = target
            spring.position = target
            spring.target = target
            spring.velocity = 0
        }
        refreshRoughTargetIfPossible()
    }

    func userScrollBegan(at date: Date) {
        userScrollLocked = true
        blurSuppressed = true
        unlockAt = nil
        blurRestoreAt = nil
        spring.stop(at: scrollOffset)
        cancelWaves()
        lastFrameDate = date
    }

    func userScrollEnded(at date: Date) {
        guard userScrollLocked else { return }
        unlockAt = date.addingTimeInterval(AppMotion.lyricsFollowResume)
        blurRestoreAt = date.addingTimeInterval(AppMotion.lyricsFollowResume)
    }

    func resumeFollowing(at date: Date) {
        userScrollLocked = false
        unlockAt = nil
        blurSuppressed = false
        blurRestoreAt = nil
        guard let activeIndex else { return }
        let target = targetOffset(for: activeIndex)
        startSpring(to: target.offset, isRough: target.isRough)
        lastFrameDate = date
    }

    func selectLine(_ index: Int, startMs: Int, at date: Date) {
        selectedIndex = index
        activeIndex = index
        selectionClearAt = date.addingTimeInterval(1.2)
        blurSuppressed = true
        blurRestoreAt = date.addingTimeInterval(3.0)
        anchorSeconds = Double(startMs) / 1_000
        anchorDate = date
        follow(index: index, previous: nil, isSeek: true, date: date)
    }

    func toggleTranslation(at date: Date) {
        if let activeIndex, let frame = lineFrames[activeIndex] {
            translationAnchor = TranslationAnchor(
                index: activeIndex,
                screenY: frame.midY - scrollOffset,
                expiresAt: date.addingTimeInterval(AppMotion.medium + 0.08)
            )
        }
        showTranslation.toggle()
    }

    func opacity(for index: Int) -> Double {
        guard let activeIndex else { return 0.3 }
        guard index != activeIndex else { return 1 }
        let distance = min(abs(index - activeIndex), 6)
        return max(0.3, 1 - Double(distance) * 0.13)
    }

    func blurRadius(for _: Int) -> CGFloat {
        0
    }

    private func effectiveSeconds(at date: Date) -> TimeInterval {
        guard isPlaying, !isBuffering else { return anchorSeconds }
        let extrapolated = anchorSeconds + max(0, date.timeIntervalSince(anchorDate))
        return duration > 0 ? min(duration, extrapolated) : extrapolated
    }

    private func updateActiveIndex(at time: TimeInterval, isSeek: Bool, date: Date) {
        guard let nextIndex = lyrics.currentIndex(at: time), nextIndex != activeIndex else { return }
        let previous = activeIndex
        activeIndex = nextIndex
        follow(index: nextIndex, previous: previous, isSeek: isSeek, date: date)
    }

    private func follow(index: Int, previous: Int?, isSeek: Bool, date: Date) {
        guard !userScrollLocked else { return }
        let target = targetOffset(for: index)
        if reduceMotion {
            spring.stop(at: target.offset)
            scrollOffset = target.offset
            cancelWaves()
            return
        }

        let isNearbyAdvance = previous.map { abs(index - $0) <= 10 } ?? false
        if isNearbyAdvance, !isSeek, !target.isRough,
           startWave(to: target.offset, activeIndex: index, date: date) {
            return
        }
        startSpring(to: target.offset, isRough: target.isRough)
    }

    private func startSpring(to target: CGFloat, isRough: Bool) {
        cancelWaves()
        spring.position = scrollOffset
        spring.target = clampedOffset(target)
        spring.velocity = 0
        spring.isRunning = abs(spring.target - spring.position) >= 0.25
        spring.isRough = isRough
        if !spring.isRunning { scrollOffset = spring.target }
    }

    private func stepScrollSpring(delta: TimeInterval) {
        guard spring.isRunning, !userScrollLocked else { return }
        var remaining = delta
        while remaining > 0 {
            let step = min(remaining, 1 / 120)
            spring.velocity += (
                Self.springStiffness * Double(spring.target - spring.position)
                    - Self.springDamping * spring.velocity
            ) * step
            spring.position += CGFloat(spring.velocity * step)
            remaining -= step
        }

        let clamped = clampedOffset(spring.position)
        if clamped != spring.position { spring.velocity = 0 }
        spring.position = clamped
        scrollOffset = clamped
        if abs(spring.target - clamped) < 0.25, abs(spring.velocity) < 4 {
            spring.stop(at: spring.target)
            scrollOffset = spring.target
        }
    }

    private func startWave(to target: CGFloat, activeIndex: Int, date: Date) -> Bool {
        let target = clampedOffset(target)
        let shift = target - scrollOffset
        guard abs(shift) >= 0.25,
              viewportHeight > 0,
              abs(shift) <= viewportHeight * 1.2 else {
            return false
        }

        let visible = lineFrames
            .filter { $0.value.maxY > scrollOffset && $0.value.minY < scrollOffset + viewportHeight }
            .map(\.key)
            .sorted()
        let firstVisible = visible.first ?? activeIndex
        let lower = max(0, firstVisible - 2)
        let upper = min(lyrics.lines.count - 1, firstVisible + 14)
        guard lower <= upper else { return false }

        spring.stop(at: target)
        scrollOffset = target
        waves = Dictionary(uniqueKeysWithValues: (lower...upper).map { index in
            let distance = abs(index - firstVisible)
            return (index, WaveState(
                offset: shift,
                velocity: 0,
                delay: waveDelay(for: distance)
            ))
        })
        waveOffsets = waves.mapValues(\.offset)
        waveStartedAt = date
        return true
    }

    private func stepWaves(delta: TimeInterval, date: Date) {
        guard let startedAt = waveStartedAt else { return }
        if date.timeIntervalSince(startedAt) >= 1.4 {
            cancelWaves()
            return
        }

        let elapsed = date.timeIntervalSince(startedAt)
        var updated: [Int: WaveState] = [:]
        for (index, var wave) in waves {
            guard elapsed >= wave.delay else {
                updated[index] = wave
                continue
            }
            var remaining = delta
            while remaining > 0 {
                let step = min(remaining, 1 / 120)
                wave.velocity += (
                    Self.waveStiffness * Double(-wave.offset)
                        - Self.waveDamping * wave.velocity
                ) * step
                wave.offset += CGFloat(wave.velocity * step)
                remaining -= step
            }
            if abs(wave.offset) >= 0.3 || abs(wave.velocity) >= 2 {
                updated[index] = wave
            }
        }
        waves = updated
        waveOffsets = updated.mapValues(\.offset)
        if updated.isEmpty { waveStartedAt = nil }
    }

    private func cancelWaves() {
        waves = [:]
        waveOffsets = [:]
        waveStartedAt = nil
    }

    private func waveDelay(for distance: Int) -> TimeInterval {
        var delay = 0.0
        var step = 0.05
        for _ in 0..<distance {
            delay += step
            step /= 1.05
        }
        return delay
    }

    private func targetOffset(for index: Int) -> (offset: CGFloat, isRough: Bool) {
        if let frame = lineFrames[index], viewportHeight > 0 {
            return (clampedOffset(frame.midY - viewportHeight * Self.scrollAnchor), false)
        }
        let maxOffset = max(0, contentHeight - viewportHeight)
        let denominator = max(1, lyrics.lines.count - 1)
        return (maxOffset * CGFloat(index) / CGFloat(denominator), true)
    }

    private func clampedOffset(_ value: CGFloat) -> CGFloat {
        min(max(0, value), max(0, contentHeight - viewportHeight))
    }

    private func refreshRoughTargetIfPossible() {
        guard spring.isRunning, spring.isRough, let activeIndex,
              lineFrames[activeIndex] != nil else { return }
        let target = targetOffset(for: activeIndex)
        spring.target = target.offset
        spring.isRough = false
    }

    private func updateDeadlines(at date: Date) {
        if let unlockAt, date >= unlockAt {
            self.unlockAt = nil
            userScrollLocked = false
            if let activeIndex {
                let target = targetOffset(for: activeIndex)
                startSpring(to: target.offset, isRough: target.isRough)
            }
        }
        if let blurRestoreAt, date >= blurRestoreAt {
            self.blurRestoreAt = nil
            blurSuppressed = false
        }
        if let selectionClearAt, date >= selectionClearAt {
            self.selectionClearAt = nil
            selectedIndex = nil
        }
        if let translationAnchor, date >= translationAnchor.expiresAt {
            self.translationAnchor = nil
        }
    }
}

private extension KaraokeLyricsViewState {
    struct ScrollSpring {
        var position: CGFloat = 0
        var target: CGFloat = 0
        var velocity = 0.0
        var isRunning = false
        var isRough = false

        mutating func stop(at position: CGFloat) {
            self.position = position
            target = position
            velocity = 0
            isRunning = false
            isRough = false
        }
    }

    struct WaveState {
        var offset: CGFloat
        var velocity: Double
        let delay: TimeInterval
    }

    struct TranslationAnchor {
        let index: Int
        let screenY: CGFloat
        let expiresAt: Date
    }
}

private struct KaraokeFrameTicker: View {
    let state: KaraokeLyricsViewState

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: !state.shouldTick)) { context in
            Color.clear
                .onChange(of: context.date, initial: true) { _, date in
                    state.tick(at: date)
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct KaraokeLyricLineView: View {
    @Environment(\.sonarReduceMotion) private var reduceMotion

    let line: KaraokeLine
    let state: KaraokeLyricsViewState
    let showTranslation: Bool
    let onSelect: () -> Void

    private var isActive: Bool { state.activeIndex == line.id }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .center, spacing: 0) {
                if isActive {
                    KaraokeTokenLine(line: line, state: state, isActive: true)
                } else {
                    Text(line.text)
                        .font(.system(size: NCMDesignTokens.Typography.lyric, weight: .medium))
                        .foregroundStyle(NCMDesignTokens.Player.tertiaryInk)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }

                if let translation = line.translation {
                    KaraokeSupplementLine(
                        text: translation,
                        size: NCMDesignTokens.Typography.lyricTranslation,
                        visible: showTranslation
                    )
                }

                if let romanization = line.romanization {
                    KaraokeSupplementLine(
                        text: romanization,
                        size: 12,
                        visible: true
                    )
                }
            }
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .buttonStyle(.plain)
        .opacity(state.opacity(for: line.id))
        .animation(
            AppMotion.emphasized(duration: AppMotion.medium, reduceMotion: reduceMotion),
            value: state.activeIndex
        )
        .accessibilityLabel(line.text)
        .accessibilityHint("双击跳转到这一句")
        .accessibilityIdentifier("karaoke-line-\(line.id)")
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }
}

private struct KaraokeTokenLine: View {
    let line: KaraokeLine
    let state: KaraokeLyricsViewState
    let isActive: Bool

    var body: some View {
        if isActive {
            TimelineView(
                .animation(
                    minimumInterval: 1 / 60,
                    paused: !state.sweepIsRunning
                )
            ) { context in
                tokens(at: state.effectiveMilliseconds(at: context.date))
            }
        } else {
            tokens(at: -.infinity)
        }
    }

    private func tokens(at milliseconds: Double) -> some View {
        KaraokeTokenWrapLayout {
            ForEach(line.tokens) { token in
                KaraokeTokenView(
                    token: token,
                    progress: isActive ? token.progress(atMilliseconds: milliseconds) : 0,
                    isActive: isActive
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

private struct KaraokeTokenView: View {
    let token: KaraokeToken
    let progress: Double
    let isActive: Bool

    @Environment(\.playerPalette) private var palette

    var body: some View {
        ZStack(alignment: .leading) {
            tokenText
                .foregroundStyle(isActive ? palette.ink.opacity(0.24) : palette.muted)
            tokenText
                .foregroundStyle(palette.ink)
                .mask(alignment: .leading) {
                    GeometryReader { geometry in
                        Color.black
                            .frame(width: geometry.size.width * min(max(progress, 0), 1))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
        }
        .fixedSize()
    }

    private var tokenText: some View {
        Text(token.text)
            .font(.system(size: NCMDesignTokens.Typography.activeLyric, weight: .bold))
            .tracking(0)
    }
}

private struct KaraokeTokenWrapLayout: Layout {
    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        layout(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = layout(
            proposal: ProposedViewSize(width: bounds.width, height: proposal.height),
            subviews: subviews
        )
        for (index, point) in result.points.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y),
                anchor: .topLeading,
                proposal: .unspecified
            )
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let availableWidth = max(1, proposal.width ?? .greatestFiniteMagnitude)
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var rows: [(range: Range<Int>, width: CGFloat, height: CGFloat)] = []
        var rowStart = 0
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for (index, size) in sizes.enumerated() {
            if index > rowStart, rowWidth + size.width > availableWidth {
                rows.append((rowStart..<index, rowWidth, rowHeight))
                rowStart = index
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += size.width
            rowHeight = max(rowHeight, size.height)
        }
        if rowStart < sizes.count {
            rows.append((rowStart..<sizes.count, rowWidth, rowHeight))
        }

        var points = Array(repeating: CGPoint.zero, count: sizes.count)
        var y: CGFloat = 0
        for row in rows {
            var x = max(0, (availableWidth - row.width) / 2)
            for index in row.range {
                points[index] = CGPoint(x: x, y: y)
                x += sizes[index].width
            }
            y += row.height
        }
        return (CGSize(width: availableWidth, height: y), points)
    }
}

private struct KaraokeSupplementLine: View {
    let text: String
    let size: CGFloat
    let visible: Bool

    @Environment(\.sonarReduceMotion) private var reduceMotion
    @State private var naturalHeight: CGFloat = 0

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: .regular))
            .foregroundStyle(NCMDesignTokens.Player.tertiaryInk)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(key: KaraokeSupplementHeightKey.self, value: geometry.size.height)
                }
            }
            .frame(height: visible ? naturalHeight : 0, alignment: .top)
            .clipped()
            .opacity(visible ? 1 : 0)
            .offset(y: visible ? 0 : 6)
            .padding(.top, visible ? 8 : 0)
            .onPreferenceChange(KaraokeSupplementHeightKey.self) { naturalHeight = $0 }
            .animation(
                AppMotion.emphasized(duration: AppMotion.medium, reduceMotion: reduceMotion),
                value: visible
            )
    }
}

private struct KaraokeMeasuredLine<Content: View>: View {
    let index: Int
    @ViewBuilder let content: Content

    var body: some View {
        content
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: KaraokeLineFramesKey.self,
                        value: [index: geometry.frame(in: .named(KaraokeCoordinateSpace.content))]
                    )
                }
            }
    }
}

private struct KaraokeLineFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]

    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

private struct KaraokeSupplementHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private enum KaraokeCoordinateSpace {
    static let content = "karaoke-lyrics-content"
}

private struct KaraokeEdgeFadeMask: View {
    let enabled: Bool
    let height: CGFloat

    var body: some View {
        if enabled, height > 0 {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.12),
                    .init(color: .black, location: 0.88),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        } else {
            Color.black
        }
    }
}

private struct KaraokeScrollBridge: UIViewRepresentable {
    let targetOffset: CGFloat
    let onMetrics: (CGFloat, CGFloat, CGFloat) -> Void
    let onUserScrollBegan: () -> Void
    let onUserScrollEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onMetrics: onMetrics,
            onUserScrollBegan: onUserScrollBegan,
            onUserScrollEnded: onUserScrollEnded
        )
    }

    func makeUIView(context: Context) -> ScrollProbeView {
        let view = ScrollProbeView()
        view.onAttach = { scrollView in context.coordinator.attach(to: scrollView) }
        return view
    }

    func updateUIView(_ uiView: ScrollProbeView, context: Context) {
        context.coordinator.update(
            targetOffset: targetOffset,
            onMetrics: onMetrics,
            onUserScrollBegan: onUserScrollBegan,
            onUserScrollEnded: onUserScrollEnded
        )
        uiView.findScrollView()
    }

    static func dismantleUIView(_ uiView: ScrollProbeView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject {
        private weak var scrollView: UIScrollView?
        private var offsetObservation: NSKeyValueObservation?
        private var sizeObservation: NSKeyValueObservation?
        private var targetOffset: CGFloat = 0
        private var onMetrics: (CGFloat, CGFloat, CGFloat) -> Void
        private var onUserScrollBegan: () -> Void
        private var onUserScrollEnded: () -> Void

        init(
            onMetrics: @escaping (CGFloat, CGFloat, CGFloat) -> Void,
            onUserScrollBegan: @escaping () -> Void,
            onUserScrollEnded: @escaping () -> Void
        ) {
            self.onMetrics = onMetrics
            self.onUserScrollBegan = onUserScrollBegan
            self.onUserScrollEnded = onUserScrollEnded
        }

        func attach(to scrollView: UIScrollView) {
            guard self.scrollView !== scrollView else { return }
            detach()
            self.scrollView = scrollView
            scrollView.panGestureRecognizer.addTarget(self, action: #selector(handlePan(_:)))
            offsetObservation = scrollView.observe(\.contentOffset, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.publishMetrics() }
            }
            sizeObservation = scrollView.observe(\.contentSize, options: [.initial, .new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.publishMetrics() }
            }
            applyTargetOffset()
        }

        func update(
            targetOffset: CGFloat,
            onMetrics: @escaping (CGFloat, CGFloat, CGFloat) -> Void,
            onUserScrollBegan: @escaping () -> Void,
            onUserScrollEnded: @escaping () -> Void
        ) {
            self.targetOffset = targetOffset
            self.onMetrics = onMetrics
            self.onUserScrollBegan = onUserScrollBegan
            self.onUserScrollEnded = onUserScrollEnded
            applyTargetOffset()
        }

        func detach() {
            if let scrollView {
                scrollView.panGestureRecognizer.removeTarget(self, action: #selector(handlePan(_:)))
            }
            offsetObservation = nil
            sizeObservation = nil
            scrollView = nil
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began:
                onUserScrollBegan()
            case .ended, .cancelled, .failed:
                onUserScrollEnded()
            default:
                break
            }
        }

        private func applyTargetOffset() {
            guard let scrollView,
                  scrollView.panGestureRecognizer.state != .began,
                  scrollView.panGestureRecognizer.state != .changed else { return }
            let maxOffset = max(0, scrollView.contentSize.height - scrollView.bounds.height)
            let target = min(max(0, targetOffset), maxOffset)
            guard abs(scrollView.contentOffset.y - target) > 0.1 else { return }
            scrollView.setContentOffset(CGPoint(x: 0, y: target), animated: false)
        }

        private func publishMetrics() {
            guard let scrollView else { return }
            onMetrics(
                max(0, scrollView.contentOffset.y),
                scrollView.bounds.height,
                scrollView.contentSize.height
            )
        }
    }
}

@MainActor
private final class ScrollProbeView: UIView {
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
