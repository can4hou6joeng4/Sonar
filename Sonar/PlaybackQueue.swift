import Foundation

public struct PlaybackQueue: Sendable, Equatable {
    public private(set) var tracks: [Track]
    public private(set) var currentIndex: Int?

    public init(tracks: [Track] = [], currentIndex: Int? = nil) {
        self.tracks = tracks
        self.currentIndex = currentIndex.flatMap { tracks.indices.contains($0) ? $0 : nil }
    }

    public var current: Track? {
        guard let currentIndex, tracks.indices.contains(currentIndex) else { return nil }
        return tracks[currentIndex]
    }

    public mutating func replace(with tracks: [Track], startingAt index: Int = 0) {
        self.tracks = tracks
        currentIndex = tracks.indices.contains(index) ? index : nil
    }

    public mutating func move(fromOffsets: IndexSet, toOffset: Int) {
        let validOffsets = IndexSet(fromOffsets.filter { tracks.indices.contains($0) })
        guard !validOffsets.isEmpty else { return }
        let currentOriginalIndex = currentIndex
        var indexedTracks = Array(tracks.enumerated())
        let moving = validOffsets.sorted().map { indexedTracks[$0] }
        for index in validOffsets.sorted(by: >) { indexedTracks.remove(at: index) }
        let removedBeforeDestination = validOffsets.filter { $0 < toOffset }.count
        let destination = min(max(toOffset - removedBeforeDestination, 0), indexedTracks.count)
        indexedTracks.insert(contentsOf: moving, at: destination)
        tracks = indexedTracks.map(\.element)
        currentIndex = currentOriginalIndex.flatMap { originalIndex in
            indexedTracks.firstIndex { $0.offset == originalIndex }
        }
    }

    public mutating func insert(_ track: Track, at index: Int) {
        let destination = min(max(index, 0), tracks.count)
        tracks.insert(track, at: destination)
        if let currentIndex, destination <= currentIndex {
            self.currentIndex = currentIndex + 1
        }
    }

    @discardableResult
    public mutating func remove(at index: Int) -> Track? {
        guard tracks.indices.contains(index) else { return nil }
        let removed = tracks.remove(at: index)
        if let currentIndex {
            if index == currentIndex {
                self.currentIndex = tracks.isEmpty ? nil : min(index, tracks.count - 1)
            } else if index < currentIndex {
                self.currentIndex = currentIndex - 1
            }
        }
        return removed
    }

    public mutating func clearUpcoming() {
        guard let currentIndex else { return }
        tracks.removeSubrange(tracks.index(after: currentIndex)..<tracks.endIndex)
    }

    public mutating func select(index: Int) {
        guard tracks.indices.contains(index) else { return }
        currentIndex = index
    }

    public mutating func advance() -> Track? {
        guard let currentIndex, tracks.indices.contains(currentIndex + 1) else { return nil }
        self.currentIndex = currentIndex + 1
        return current
    }

    public mutating func retreat() -> Track? {
        guard let currentIndex, tracks.indices.contains(currentIndex - 1) else { return nil }
        self.currentIndex = currentIndex - 1
        return current
    }
}
