import Foundation

public struct PlaybackQueue: Sendable, Equatable {
    private struct Entry: Sendable, Equatable, Identifiable {
        let id: UUID
        var track: Track

        init(id: UUID = UUID(), track: Track) {
            self.id = id
            self.track = track
        }
    }

    private var canonicalEntries: [Entry]
    private var effectiveEntries: [Entry]
    private var currentEntryID: UUID?
    private var history: [UUID] = []
    private var forwardHistory: [UUID] = []
    private var isShuffled = false
    private let randomIndex: @Sendable (Range<Int>) -> Int

    public init(
        tracks: [Track] = [],
        currentIndex: Int? = nil,
        randomIndex: @escaping @Sendable (Range<Int>) -> Int = { Int.random(in: $0) }
    ) {
        let entries = tracks.map { Entry(track: $0) }
        canonicalEntries = entries
        effectiveEntries = entries
        currentEntryID = currentIndex.flatMap { entries.indices.contains($0) ? entries[$0].id : nil }
        self.randomIndex = randomIndex
    }

    public static func == (lhs: PlaybackQueue, rhs: PlaybackQueue) -> Bool {
        lhs.canonicalEntries == rhs.canonicalEntries
            && lhs.effectiveEntries == rhs.effectiveEntries
            && lhs.currentEntryID == rhs.currentEntryID
            && lhs.history == rhs.history
            && lhs.forwardHistory == rhs.forwardHistory
            && lhs.isShuffled == rhs.isShuffled
    }

    public var tracks: [Track] { effectiveEntries.map(\.track) }

    public var currentIndex: Int? {
        guard let currentEntryID else { return nil }
        return effectiveEntries.firstIndex { $0.id == currentEntryID }
    }

    public var current: Track? {
        guard let currentEntryID else { return nil }
        return effectiveEntries.first { $0.id == currentEntryID }?.track
    }

    public func peekNext() -> Track? {
        guard let currentEntryID,
              let currentIndex = effectiveEntries.firstIndex(where: { $0.id == currentEntryID }) else {
            return effectiveEntries.first?.track
        }
        let nextIndex = currentIndex + 1
        if effectiveEntries.indices.contains(nextIndex) {
            return effectiveEntries[nextIndex].track
        }
        return effectiveEntries.first?.track
    }

    public var shuffleEnabled: Bool { isShuffled }

    public mutating func replace(with tracks: [Track], startingAt index: Int = 0) {
        let entries = tracks.map { Entry(track: $0) }
        canonicalEntries = entries
        history.removeAll()
        forwardHistory.removeAll()
        currentEntryID = entries.indices.contains(index) ? entries[index].id : nil
        effectiveEntries = isShuffled ? shuffledCycle(anchoredAt: currentEntryID) : entries
    }

    public mutating func setShuffled(_ shuffled: Bool) {
        guard shuffled != isShuffled else { return }
        isShuffled = shuffled
        effectiveEntries = shuffled ? shuffledCycle(anchoredAt: currentEntryID) : canonicalEntries
        forwardHistory.removeAll()
        pruneNavigationState()
    }

    public mutating func move(fromOffsets: IndexSet, toOffset: Int) {
        let validOffsets = IndexSet(fromOffsets.filter { effectiveEntries.indices.contains($0) })
        guard !validOffsets.isEmpty else { return }
        let moving = validOffsets.sorted().map { effectiveEntries[$0] }
        for index in validOffsets.sorted(by: >) { effectiveEntries.remove(at: index) }
        let removedBeforeDestination = validOffsets.filter { $0 < toOffset }.count
        let destination = min(max(toOffset - removedBeforeDestination, 0), effectiveEntries.count)
        effectiveEntries.insert(contentsOf: moving, at: destination)
        if !isShuffled { canonicalEntries = effectiveEntries }
        forwardHistory.removeAll()
    }

    public mutating func insert(_ track: Track, at index: Int) {
        insert(track, at: index, clearingForwardHistory: true)
    }

    public mutating func append(_ track: Track) {
        insert(track, at: effectiveEntries.endIndex, clearingForwardHistory: false)
    }

    public mutating func updateTrack(_ track: Track) {
        for index in canonicalEntries.indices where canonicalEntries[index].track.musicID == track.musicID {
            canonicalEntries[index].track = track
        }
        for index in effectiveEntries.indices where effectiveEntries[index].track.musicID == track.musicID {
            effectiveEntries[index].track = track
        }
    }

    private mutating func insert(
        _ track: Track,
        at index: Int,
        clearingForwardHistory: Bool
    ) {
        let entry = Entry(track: track)
        let destination = min(max(index, 0), effectiveEntries.count)
        if isShuffled {
            effectiveEntries.insert(entry, at: destination)
            let canonicalDestination = canonicalInsertionIndex(forEffectiveIndex: destination)
            canonicalEntries.insert(entry, at: canonicalDestination)
        } else {
            canonicalEntries.insert(entry, at: destination)
            effectiveEntries = canonicalEntries
        }
        if clearingForwardHistory { forwardHistory.removeAll() }
    }

    @discardableResult
    public mutating func remove(at index: Int) -> Track? {
        guard effectiveEntries.indices.contains(index) else { return nil }
        let removed = effectiveEntries.remove(at: index)
        canonicalEntries.removeAll { $0.id == removed.id }

        if currentEntryID == removed.id {
            currentEntryID = effectiveEntries.isEmpty
                ? nil
                : effectiveEntries[min(index, effectiveEntries.count - 1)].id
        }
        forwardHistory.removeAll()
        pruneNavigationState()
        return removed.track
    }

    public mutating func clearUpcoming() {
        guard let currentIndex, effectiveEntries.indices.contains(currentIndex) else { return }
        let upcoming = effectiveEntries.index(after: currentIndex)..<effectiveEntries.endIndex
        let removedIDs = Set(effectiveEntries[upcoming].map(\.id))
        effectiveEntries.removeSubrange(upcoming)
        canonicalEntries.removeAll { removedIDs.contains($0.id) }
        forwardHistory.removeAll()
        pruneNavigationState()
    }

    public mutating func select(index: Int) {
        guard effectiveEntries.indices.contains(index) else { return }
        transition(to: effectiveEntries[index].id, clearForward: true)
    }

    @discardableResult
    public mutating func advance(wrapping: Bool = false) -> Track? {
        guard let currentEntryID, let currentIndex else { return nil }

        if let forwardID = popLastValid(from: &forwardHistory) {
            transition(to: forwardID, clearForward: false)
            return current
        }

        let targetID: UUID?
        if effectiveEntries.indices.contains(currentIndex + 1) {
            targetID = effectiveEntries[currentIndex + 1].id
        } else if isShuffled, effectiveEntries.count > 1 {
            effectiveEntries = shuffledCycle(anchoredAt: currentEntryID)
            targetID = effectiveEntries.dropFirst().first?.id
        } else if wrapping {
            targetID = effectiveEntries.first?.id
        } else {
            targetID = nil
        }

        guard let targetID else { return nil }
        transition(to: targetID, clearForward: true)
        return current
    }

    @discardableResult
    public mutating func retreat(wrapping: Bool = false) -> Track? {
        guard let currentEntryID, let currentIndex else { return nil }

        if let previousID = popLastValid(from: &history) {
            forwardHistory.append(currentEntryID)
            self.currentEntryID = previousID
            return current
        }

        guard !isShuffled, wrapping else { return nil }
        let targetIndex = currentIndex > 0 ? currentIndex - 1 : effectiveEntries.count - 1
        guard effectiveEntries.indices.contains(targetIndex) else { return nil }
        let targetID = effectiveEntries[targetIndex].id
        guard targetID != currentEntryID else { return current }
        forwardHistory.append(currentEntryID)
        self.currentEntryID = targetID
        return current
    }

    private mutating func transition(to targetID: UUID, clearForward: Bool) {
        guard effectiveEntries.contains(where: { $0.id == targetID }) else { return }
        if let currentEntryID, currentEntryID != targetID {
            history.append(currentEntryID)
        }
        currentEntryID = targetID
        if clearForward { forwardHistory.removeAll() }
    }

    private func shuffledCycle(anchoredAt currentID: UUID?) -> [Entry] {
        guard let currentID,
              let currentIndex = canonicalEntries.firstIndex(where: { $0.id == currentID }) else {
            return shuffled(canonicalEntries)
        }
        let current = canonicalEntries[currentIndex]
        let remaining = canonicalEntries.filter { $0.id != currentID }
        let naturalContinuation = Array(canonicalEntries.dropFirst(currentIndex + 1))
            + Array(canonicalEntries.prefix(currentIndex))
        return [current] + shuffled(remaining, avoiding: naturalContinuation)
    }

    private func shuffled(_ entries: [Entry], avoiding naturalOrder: [Entry]? = nil) -> [Entry] {
        guard entries.count > 1 else { return entries }
        var result = entries
        for upperBound in stride(from: result.count, through: 2, by: -1) {
            let range = 0..<upperBound
            let proposed = randomIndex(range)
            let selected = range.contains(proposed) ? proposed : range.lowerBound
            result.swapAt(upperBound - 1, selected)
        }
        let orderToAvoid = naturalOrder ?? entries
        if result == orderToAvoid {
            result.swapAt(0, 1)
        }
        return result
    }

    private func canonicalInsertionIndex(forEffectiveIndex index: Int) -> Int {
        if index > 0 {
            let previousID = effectiveEntries[index - 1].id
            if let previous = canonicalEntries.firstIndex(where: { $0.id == previousID }) {
                return previous + 1
            }
        }
        if effectiveEntries.indices.contains(index + 1) {
            let nextID = effectiveEntries[index + 1].id
            if let next = canonicalEntries.firstIndex(where: { $0.id == nextID }) {
                return next
            }
        }
        return canonicalEntries.count
    }

    private mutating func pruneNavigationState() {
        let validIDs = Set(canonicalEntries.map(\.id))
        history.removeAll { !validIDs.contains($0) }
        forwardHistory.removeAll { !validIDs.contains($0) }
        if let currentEntryID, !validIDs.contains(currentEntryID) {
            self.currentEntryID = effectiveEntries.first?.id
        }
    }

    private func popLastValid(from values: inout [UUID]) -> UUID? {
        let validIDs = Set(canonicalEntries.map(\.id))
        while let candidate = values.popLast() {
            if validIDs.contains(candidate) { return candidate }
        }
        return nil
    }
}
