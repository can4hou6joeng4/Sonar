import Foundation
import Observation

@MainActor
@Observable
final class SearchViewModel {
    /// Keep the first search response compact so song results remain the primary
    /// task on a small screen. Additional pages are fetched only after the user
    /// explicitly expands the artist section.
    static let artistPreviewLimit = 3

    static let fallbackHotSearches = [
        "晴天", "一路向北", "起风了", "海阔天空", "稻香", "富士山下",
        "七里香", "后来", "若月亮没来", "爱错", "唯一", "珠玉",
    ]

    private struct SourceResult: Sendable {
        let source: MusicSource
        let tracks: [Track]
        let errorMessage: String?
    }

    private struct ArtistSourceResult: Sendable {
        let source: MusicSource
        let page: ArtistSearchPage?
        let errorMessage: String?

        var artists: [ArtistSummary] { page?.list ?? [] }
    }

    private struct ArtistPaginationState: Sendable {
        var artists: [ArtistSummary]
        var total: Int
        var page: Int
        var limit: Int
        var hasMore: Bool
    }

    var query = ""
    var results: [Track] = []
    var artistResults: [ArtistSummary] = []
    var suggestions: [String] = []
    var hotSearches = fallbackHotSearches
    var isLoading = false
    var isLoadingArtists = false
    var isLoadingSuggestions = false
    var isLoadingHotSearches = false
    var hasSearched = false
    var errorMessage: String?
    var failedSource: MusicSource?
    var isRetryingFailedSource = false
    var failedArtistSources: Set<MusicSource> = []
    var retryingArtistSources: Set<MusicSource> = []
    var isArtistResultsExpanded = false
    var isLoadingMoreArtists = false
    var artistExpansionFailedSources: Set<MusicSource> = []
    var retryingArtistExpansionSources: Set<MusicSource> = []
    var hotSearchErrorMessage: String?
    private var suggestionTask: Task<Void, Never>?
    private var submittedSearchTask: Task<Void, Never>?
    private var songFailures: [(MusicSource, String)] = []
    private var suggestionGeneration = 0
    private var hotSearchGeneration = 0
    private var searchGeneration = 0
    private var hasLoadedHotSearches = false
    private var activeSearchKeyword: String?
    private var submittedKeyword: String?
    private var artistSourceStates: [MusicSource: ArtistPaginationState] = [:]
    private let runtime: SourceRuntime

    init(runtime: SourceRuntime) { self.runtime = runtime }

    var partialSourceWarning: String? {
        guard let failedSource, !results.isEmpty else { return nil }
        let availableSource = failedSource == .wy ? MusicSource.tx : .wy
        return "\(failedSource.displayName) 搜索暂不可用，当前显示\(availableSource.displayName)结果"
    }


    var songSearchErrorMessage: String? {
        guard !isLoading, results.isEmpty, !songFailures.isEmpty else { return nil }
        return "歌曲搜索失败：\(songFailures.map(\.1).joined(separator: "；"))"
    }

    var artistSourceWarnings: [MusicSource] {
        failedArtistSources.sorted { $0.rawValue < $1.rawValue }
    }

    var artistExpansionWarnings: [MusicSource] {
        artistExpansionFailedSources.sorted { $0.rawValue < $1.rawValue }
    }

    var visibleArtistResults: [ArtistSummary] {
        isArtistResultsExpanded
            ? artistResults
            : Array(artistResults.prefix(Self.artistPreviewLimit))
    }

    var artistRemainingCount: Int {
        let unloaded = artistSourceStates.values.reduce(into: 0) { result, state in
            let knownRemaining = max(0, state.total - state.artists.count)
            result += knownRemaining > 0 ? knownRemaining : (state.hasMore ? state.limit : 0)
        }
        let loadedButHidden = isArtistResultsExpanded
            ? 0
            : max(0, artistResults.count - Self.artistPreviewLimit)
        return unloaded + loadedButHidden
    }

    var canExpandArtistResults: Bool {
        (!isArtistResultsExpanded && artistResults.count > Self.artistPreviewLimit)
            || artistSourceStates.values.contains { $0.hasMore }
    }

    func loadHotSearchesIfNeeded() async {
        guard !hasLoadedHotSearches, !isLoadingHotSearches else { return }
        await refreshHotSearches()
    }

    func refreshHotSearches() async {
        hotSearchGeneration += 1
        let generation = hotSearchGeneration
        isLoadingHotSearches = true
        hotSearchErrorMessage = nil

        var failures: [String] = []
        for source in [MusicSource.wy, .tx] {
            do {
                let values = normalizeHotSearches(try await runtime.hotSearch(source: source))
                guard generation == hotSearchGeneration else { return }
                if !values.isEmpty {
                    hotSearches = values
                    isLoadingHotSearches = false
                    hasLoadedHotSearches = true
                    return
                }
            } catch is CancellationError {
                guard generation == hotSearchGeneration else { return }
                isLoadingHotSearches = false
                return
            } catch {
                guard generation == hotSearchGeneration else { return }
                failures.append(error.localizedDescription)
            }
        }

        guard generation == hotSearchGeneration else { return }
        isLoadingHotSearches = false
        hasLoadedHotSearches = true
        hotSearchErrorMessage = failures.isEmpty ? "暂时没有热门搜索" : "热门搜索暂不可用"
    }

    func queryChanged() {
        suggestionTask?.cancel()
        suggestionGeneration += 1
        suggestions = []
        isLoadingSuggestions = false
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let changesSubmittedSearch = submittedKeyword != nil && submittedKeyword != keyword
        if (activeSearchKeyword != nil && activeSearchKeyword != keyword) || changesSubmittedSearch {
            submittedSearchTask?.cancel()
            songFailures = []
            searchGeneration += 1
            activeSearchKeyword = nil
            isLoading = false
            isLoadingArtists = false
            submittedKeyword = nil
        }
        guard !keyword.isEmpty else {
            suggestions = []
            results = []
            resetArtistResults()
            errorMessage = nil
            failedSource = nil
            isRetryingFailedSource = false
            failedArtistSources = []
            retryingArtistSources = []
            hasSearched = false
            submittedKeyword = nil
            return
        }
        if keyword != submittedKeyword {
            results = []
            resetArtistResults()
            errorMessage = nil
            failedSource = nil
            isRetryingFailedSource = false
            failedArtistSources = []
            retryingArtistSources = []
            hasSearched = false
        }
        guard keyword != submittedKeyword, keyword.count >= 2 else {
            return
        }
        let generation = suggestionGeneration
        isLoadingSuggestions = true
        suggestionTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(320))
                let values = try await runtime.tipSearch(keyword)
                guard !Task.isCancelled,
                      generation == suggestionGeneration,
                      query.trimmingCharacters(in: .whitespacesAndNewlines) == keyword else { return }
                suggestions = values
                isLoadingSuggestions = false
            } catch {
                guard generation == suggestionGeneration,
                      query.trimmingCharacters(in: .whitespacesAndNewlines) == keyword else { return }
                suggestions = []
                isLoadingSuggestions = false
            }
        }
    }

    private var liveSearchTask: Task<Void, Never>?

    func liveSearch(debounceDuration: Duration = .milliseconds(350)) {
        liveSearchTask?.cancel()
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else {
            queryChanged()
            return
        }
        queryChanged()
        liveSearchTask = Task {
            try? await Task.sleep(for: debounceDuration)
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    func cancelLiveSearch() {
        liveSearchTask?.cancel()
    }

    func search() async {
        liveSearchTask?.cancel()
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        submittedSearchTask?.cancel()
        searchGeneration += 1
        let generation = searchGeneration
        songFailures = []
        suggestionTask?.cancel()
        suggestionGeneration += 1
        suggestions = []
        isLoadingSuggestions = false
        guard !keyword.isEmpty else {
            results = []
            resetArtistResults()
            errorMessage = nil
            failedSource = nil
            isRetryingFailedSource = false
            failedArtistSources = []
            retryingArtistSources = []
            isLoading = false
            isLoadingArtists = false
            hasSearched = false
            activeSearchKeyword = nil
            submittedKeyword = nil
            return
        }
        submittedKeyword = keyword
        activeSearchKeyword = keyword
        results = []
        resetArtistResults()
        hasSearched = false
        isLoading = true
        isLoadingArtists = true
        errorMessage = nil
        failedSource = nil
        isRetryingFailedSource = false
        failedArtistSources = []
        retryingArtistSources = []

        let task = Task {
            async let songs: Void = loadSubmittedSongs(keyword, generation: generation)
            async let artists: Void = loadSubmittedArtists(keyword, generation: generation)
            _ = await (songs, artists)
        }
        submittedSearchTask = task
        await task.value
        guard isCurrentSearch(generation, keyword: keyword) else { return }
        submittedSearchTask = nil
        activeSearchKeyword = nil
    }

    private func loadSubmittedSongs(_ keyword: String, generation: Int) async {
        async let wyResult = search(keyword, source: .wy)
        async let txResult = search(keyword, source: .tx)
        let sourceResults = await [wyResult, txResult]
        guard !Task.isCancelled, isCurrentSearch(generation, keyword: keyword) else { return }
        results = SearchResultRanker.rank(deduplicated(sourceResults.flatMap(\.tracks)), for: keyword)
        songFailures = sourceResults.compactMap { result in
            result.errorMessage.map { (result.source, $0) }
        }
        failedSource = results.isEmpty ? nil : songFailures.first?.0
        isLoading = false
        hasSearched = true
        updateSearchError()
    }

    private func loadSubmittedArtists(_ keyword: String, generation: Int) async {
        let candidates = Self.candidateArtistKeywords(for: keyword)
        async let wyArtists = searchArtists(candidates: candidates, source: .wy, page: 1, limit: Self.artistPreviewLimit)
        async let txArtists = searchArtists(candidates: candidates, source: .tx, page: 1, limit: Self.artistPreviewLimit)
        let sourceResults = await [wyArtists, txArtists]
        guard !Task.isCancelled, isCurrentSearch(generation, keyword: keyword) else { return }
        artistSourceStates = makeArtistSourceStates(from: sourceResults)
        artistResults = rankedArtists(for: keyword)
        failedArtistSources = Set(sourceResults.filter { $0.errorMessage != nil }.map(\.source))
        isLoadingArtists = false
        hasSearched = true
        updateSearchError()
    }

    private func updateSearchError() {
        // A still-pending section may produce usable results. Do not announce a
        // whole-query failure or empty state before both sections have finished.
        guard !isLoading, !isLoadingArtists, results.isEmpty, artistResults.isEmpty else {
            errorMessage = nil
            return
        }
        if !songFailures.isEmpty {
            errorMessage = "搜索失败：\(songFailures.map(\.1).joined(separator: "；"))"
        } else {
            errorMessage = failedArtistSources.isEmpty ? nil : "歌手搜索暂不可用，请重试"
        }
    }

    /// Expands the artist section and fetches exactly one bounded page per
    /// source. The first page is deliberately not re-fetched here.
    func expandArtistResults() async {
        isArtistResultsExpanded = true
        await loadMoreArtists()
    }

    func collapseArtistResults() {
        isArtistResultsExpanded = false
    }

    /// Loads the next page for each source that still has data. A caller may
    /// invoke this again from the footer to progressively reveal a very large
    /// result set without issuing an unbounded burst of requests.
    func loadMoreArtists() async {
        guard isArtistResultsExpanded,
              !isLoadingMoreArtists,
              let keyword = submittedKeyword,
              query.trimmingCharacters(in: .whitespacesAndNewlines) == keyword else { return }

        let requests = MusicSource.allCases.compactMap { source -> (MusicSource, Int)? in
            guard let state = artistSourceStates[source],
                  state.hasMore,
                  !artistExpansionFailedSources.contains(source) else { return nil }
            return (source, state.page + 1)
        }
        guard !requests.isEmpty else { return }

        let generation = searchGeneration
        isLoadingMoreArtists = true
        var tasks: [Task<ArtistSourceResult, Never>] = []
        tasks.reserveCapacity(requests.count)
        for (source, page) in requests {
            tasks.append(Task {
                await self.searchArtists(
                    keyword,
                    source: source,
                    page: page,
                    limit: Self.artistPreviewLimit
                )
            })
        }

        var pageResults: [ArtistSourceResult] = []
        pageResults.reserveCapacity(tasks.count)
        for task in tasks {
            pageResults.append(await task.value)
        }

        guard generation == searchGeneration,
              submittedKeyword == keyword,
              query.trimmingCharacters(in: .whitespacesAndNewlines) == keyword else { return }

        for result in pageResults {
            if let page = result.page, result.errorMessage == nil {
                mergeArtistPage(page, source: result.source)
                artistExpansionFailedSources.remove(result.source)
            } else if result.errorMessage != nil {
                artistExpansionFailedSources.insert(result.source)
            }
        }
        artistResults = rankedArtists(for: keyword)
        isLoadingMoreArtists = false
    }

    func retryArtistExpansion(_ source: MusicSource) async {
        guard artistExpansionFailedSources.contains(source),
              !retryingArtistExpansionSources.contains(source),
              isArtistResultsExpanded,
              let keyword = submittedKeyword,
              let state = artistSourceStates[source],
              query.trimmingCharacters(in: .whitespacesAndNewlines) == keyword else { return }

        let generation = searchGeneration
        retryingArtistExpansionSources.insert(source)
        let result = await searchArtists(
            keyword,
            source: source,
            page: state.page + 1,
            limit: Self.artistPreviewLimit
        )
        guard generation == searchGeneration,
              submittedKeyword == keyword,
              query.trimmingCharacters(in: .whitespacesAndNewlines) == keyword else { return }

        retryingArtistExpansionSources.remove(source)
        if let page = result.page, result.errorMessage == nil {
            mergeArtistPage(page, source: source)
            artistExpansionFailedSources.remove(source)
            artistResults = rankedArtists(for: keyword)
        }
    }

    func retryArtistSource(_ source: MusicSource) async {
        guard failedArtistSources.contains(source),
              let keyword = submittedKeyword,
              query.trimmingCharacters(in: .whitespacesAndNewlines) == keyword,
              !retryingArtistSources.contains(source) else { return }
        let generation = searchGeneration
        retryingArtistSources.insert(source)
        let result = await searchArtists(
            keyword,
            source: source,
            page: 1,
            limit: Self.artistPreviewLimit
        )
        guard generation == searchGeneration,
              submittedKeyword == keyword,
              query.trimmingCharacters(in: .whitespacesAndNewlines) == keyword else { return }
        retryingArtistSources.remove(source)
        guard let page = result.page, result.errorMessage == nil else { return }
        artistSourceStates[source] = makeArtistSourceState(page)
        artistResults = rankedArtists(for: keyword)
        failedArtistSources.remove(source)
        updateSearchError()
    }

    func retryFailedSource() async {
        guard let source = failedSource,
              let keyword = submittedKeyword,
              query.trimmingCharacters(in: .whitespacesAndNewlines) == keyword,
              !isRetryingFailedSource else { return }
        let generation = searchGeneration
        isRetryingFailedSource = true
        let sourceResult = await search(keyword, source: source)
        guard generation == searchGeneration,
              submittedKeyword == keyword,
              query.trimmingCharacters(in: .whitespacesAndNewlines) == keyword else { return }

        isRetryingFailedSource = false
        if sourceResult.errorMessage == nil {
            results = SearchResultRanker.rank(
                deduplicated(results + sourceResult.tracks),
                for: keyword
            )
            failedSource = nil
            songFailures.removeAll { $0.0 == source }
            updateSearchError()
        }
    }

    private func search(_ keyword: String, source: MusicSource) async -> SourceResult {
        do {
            return SourceResult(
                source: source,
                tracks: try await runtime.search(keyword, source: source, page: 1).list,
                errorMessage: nil
            )
        } catch is CancellationError {
            return SourceResult(source: source, tracks: [], errorMessage: nil)
        } catch {
            return SourceResult(source: source, tracks: [], errorMessage: error.localizedDescription)
        }
    }

    static func candidateArtistKeywords(for rawQuery: String) -> [String] {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var candidates: [String] = [trimmed]

        if trimmed.contains(" - ") {
            let parts = trimmed.components(separatedBy: " - ")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for part in parts.reversed() where !candidates.contains(part) {
                candidates.append(part)
            }
        }

        let spaceSegments = trimmed.components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if spaceSegments.count > 1 {
            for seg in spaceSegments where !candidates.contains(seg) && seg.count >= 2 {
                candidates.append(seg)
            }
        }

        return candidates
    }

    private func searchArtists(
        candidates: [String],
        source: MusicSource,
        page: Int,
        limit: Int
    ) async -> ArtistSourceResult {
        guard let primary = candidates.first else {
            return ArtistSourceResult(source: source, page: nil, errorMessage: nil)
        }
        let primaryResult = await searchArtists(primary, source: source, page: page, limit: limit)
        if !(primaryResult.page?.list.isEmpty ?? true) || candidates.count <= 1 {
            return primaryResult
        }
        for candidate in candidates.dropFirst() {
            let candidateResult = await searchArtists(candidate, source: source, page: page, limit: limit)
            if let page = candidateResult.page, !page.list.isEmpty {
                return candidateResult
            }
        }
        return primaryResult
    }

    private func searchArtists(
        _ keyword: String,
        source: MusicSource,
        page: Int,
        limit: Int
    ) async -> ArtistSourceResult {
        do {
            return ArtistSourceResult(
                source: source,
                page: try await runtime.searchArtists(
                    keyword,
                    source: source,
                    page: page,
                    limit: limit
                ),
                errorMessage: nil
            )
        } catch is CancellationError {
            return ArtistSourceResult(source: source, page: nil, errorMessage: nil)
        } catch {
            return ArtistSourceResult(source: source, page: nil, errorMessage: error.localizedDescription)
        }
    }

    private func isCurrentSearch(_ generation: Int, keyword: String) -> Bool {
        generation == searchGeneration
            && activeSearchKeyword == keyword
            && query.trimmingCharacters(in: .whitespacesAndNewlines) == keyword
    }

    nonisolated func deduplicated(_ tracks: [Track]) -> [Track] {
        var seen = Set<String>()
        return tracks.filter { seen.insert($0.musicID).inserted }
    }

    nonisolated func deduplicated(_ artists: [ArtistSummary]) -> [ArtistSummary] {
        var seen = Set<String>()
        return artists.filter { seen.insert($0.stableID).inserted }
    }

    private func resetArtistResults() {
        artistResults = []
        artistSourceStates = [:]
        isArtistResultsExpanded = false
        isLoadingMoreArtists = false
        artistExpansionFailedSources = []
        retryingArtistExpansionSources = []
    }

    private func makeArtistSourceStates(
        from results: [ArtistSourceResult]
    ) -> [MusicSource: ArtistPaginationState] {
        Dictionary(uniqueKeysWithValues: results.compactMap { result in
            guard let page = result.page, result.errorMessage == nil else { return nil }
            return (result.source, makeArtistSourceState(page))
        })
    }

    private func makeArtistSourceState(_ page: ArtistSearchPage) -> ArtistPaginationState {
        let artists = deduplicated(Array(page.list.prefix(Self.artistPreviewLimit)))
        let total = max(page.total, artists.count)
        let hasMore = !artists.isEmpty && (
            page.hasMore || page.list.count > artists.count || total > artists.count
        )
        return ArtistPaginationState(
            artists: artists,
            total: total,
            page: page.page,
            limit: Self.artistPreviewLimit,
            hasMore: hasMore
        )
    }

    private func mergeArtistPage(_ page: ArtistSearchPage, source: MusicSource) {
        let incoming = deduplicated(Array(page.list.prefix(Self.artistPreviewLimit)))
        guard !incoming.isEmpty else {
            if var state = artistSourceStates[source] {
                state.hasMore = false
                artistSourceStates[source] = state
            }
            return
        }

        var state = artistSourceStates[source] ?? ArtistPaginationState(
            artists: [],
            total: 0,
            page: max(1, page.page - 1),
            limit: Self.artistPreviewLimit,
            hasMore: true
        )
        state.artists = deduplicated(state.artists + incoming)
        state.total = max(state.total, page.total, state.artists.count)
        state.page = max(state.page, page.page)
        state.limit = Self.artistPreviewLimit
        state.hasMore = page.hasMore || page.list.count > incoming.count || state.artists.count < state.total
        artistSourceStates[source] = state
    }

    private func rankedArtists(for keyword: String) -> [ArtistSummary] {
        let artists = MusicSource.allCases.flatMap { artistSourceStates[$0]?.artists ?? [] }
        return ArtistResultRanker.rank(deduplicated(artists), for: keyword)
    }

    private func normalizeHotSearches(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
        .prefix(Self.fallbackHotSearches.count)
        .map { $0 }
    }
}

enum ArtistResultRanker {
    static func rank(_ artists: [ArtistSummary], for query: String) -> [ArtistSummary] {
        let target = normalized(query)
        return artists.enumerated().sorted { lhs, rhs in
            let leftNorm = normalized(lhs.element.name)
            let rightNorm = normalized(rhs.element.name)

            let leftExact = leftNorm == target
            let rightExact = rightNorm == target
            if leftExact != rightExact { return leftExact }

            let leftContained = !leftNorm.isEmpty && (target.contains(leftNorm) || leftNorm.contains(target))
            let rightContained = !rightNorm.isEmpty && (target.contains(rightNorm) || rightNorm.contains(target))
            if leftContained != rightContained { return leftContained }

            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .filter { $0.isLetter || $0.isNumber }
    }
}

enum SearchResultRanker {
    private static let artistSeparators = CharacterSet(charactersIn: "、&;/,，|")
    private static let asciiDerivativeMarkers = Set(["live", "dj", "cover", "remix", "montagem"])
    private static let derivativeMarkers = [
        "live", "dj", "伴奏", "钢琴", "cover", "remix", "montagem", "原唱",
    ]

    static func rank(_ tracks: [Track], for query: String) -> [Track] {
        let normalizedQuery = normalized(query)
        return tracks.enumerated()
            .map {
                (
                    index: $0.offset,
                    track: $0.element,
                    score: score($0.element, query: normalizedQuery, rawQuery: query)
                )
            }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.index < $1.index
            }
            .map(\.track)
    }

    private static func score(_ track: Track, query: String, rawQuery: String) -> Int {
        let title = normalized(track.title)
        let artists = artistSegments(track.artist)
        var score = 0

        if title == query {
            score += 1_200
        } else if !title.isEmpty, query.hasPrefix(title) || query.hasSuffix(title) {
            score += 950
        } else if !title.isEmpty, query.contains(title) {
            score += 800
        } else if !query.isEmpty, title.contains(query) {
            score += 450
        }

        let requestedArtists = artists.filter { !$0.isEmpty && query.contains($0) }
        if !requestedArtists.isEmpty {
            score += 420
            if artists.count == 1 {
                score += 180
            } else {
                score -= min(240, (artists.count - 1) * 80)
            }
        }

        let searchableMetadata = "\(track.title) \(track.artist)"
        for marker in derivativeMarkers {
            if containsDerivativeMarker(marker, in: searchableMetadata),
               !containsDerivativeMarker(marker, in: rawQuery) {
                score -= 700
            }
        }
        return score
    }

    private static func containsDerivativeMarker(_ marker: String, in value: String) -> Bool {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: .current
        )
        guard asciiDerivativeMarkers.contains(marker) else {
            return normalized(folded).contains(normalized(marker))
        }
        let pattern = "(^|[^a-z])\(NSRegularExpression.escapedPattern(for: marker))([^a-z]|$)"
        return folded.range(of: pattern, options: .regularExpression) != nil
    }

    private static func artistSegments(_ value: String) -> [String] {
        value.components(separatedBy: artistSeparators)
            .map(normalized)
            .filter { !$0.isEmpty }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}

enum SearchStorageMigration {
    static let legacyHistoryKey = "ncmSearchHistory"

    static func clearLegacyHistory(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: legacyHistoryKey)
    }
}
