import Observation

@MainActor
@Observable
final class SearchViewModel {
    private struct SourceResult: Sendable {
        let tracks: [Track]
        let errorMessage: String?
    }

    var query = ""
    var results: [Track] = []
    var suggestions: [String] = []
    var isLoading = false
    var hasSearched = false
    var errorMessage: String?
    private var suggestionTask: Task<Void, Never>?
    private var suggestionGeneration = 0
    private var searchGeneration = 0
    private var activeSearchKeyword: String?
    private var submittedKeyword: String?
    private let runtime: SourceRuntime

    init(runtime: SourceRuntime) { self.runtime = runtime }

    func queryChanged() {
        suggestionTask?.cancel()
        suggestionGeneration += 1
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if activeSearchKeyword != nil, activeSearchKeyword != keyword {
            searchGeneration += 1
            activeSearchKeyword = nil
            isLoading = false
        }
        guard !keyword.isEmpty else {
            suggestions = []
            results = []
            errorMessage = nil
            hasSearched = false
            submittedKeyword = nil
            return
        }
        if keyword != submittedKeyword {
            results = []
            errorMessage = nil
            hasSearched = false
        }
        guard keyword != submittedKeyword, keyword.count >= 2 else {
            suggestions = []
            return
        }
        let generation = suggestionGeneration
        suggestionTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(320))
                let values = try await runtime.tipSearch(keyword)
                guard !Task.isCancelled,
                      generation == suggestionGeneration,
                      query.trimmingCharacters(in: .whitespacesAndNewlines) == keyword else { return }
                suggestions = values
            } catch {
                guard generation == suggestionGeneration else { return }
                suggestions = []
            }
        }
    }

    func search() async {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchGeneration += 1
        let generation = searchGeneration
        suggestionTask?.cancel()
        suggestionGeneration += 1
        suggestions = []
        guard !keyword.isEmpty else {
            results = []
            errorMessage = nil
            isLoading = false
            hasSearched = false
            activeSearchKeyword = nil
            submittedKeyword = nil
            return
        }
        submittedKeyword = keyword
        activeSearchKeyword = keyword
        results = []
        hasSearched = false
        isLoading = true
        errorMessage = nil

        async let wyResult = search(keyword, source: .wy)
        async let txResult = search(keyword, source: .tx)
        let sourceResults = await [wyResult, txResult]
        guard isCurrentSearch(generation, keyword: keyword) else { return }

        var seen = Set<String>()
        let merged = sourceResults
            .flatMap(\.tracks)
            .filter { seen.insert($0.musicID).inserted }
        let failures = sourceResults.compactMap(\.errorMessage)
        finishSearch(
            merged,
            errorMessage: merged.isEmpty && !failures.isEmpty
                ? "搜索失败：\(failures.joined(separator: "；"))"
                : nil,
            generation: generation,
            keyword: keyword
        )
    }

    private func search(_ keyword: String, source: MusicSource) async -> SourceResult {
        do {
            return SourceResult(
                tracks: try await runtime.search(keyword, source: source, page: 1).list,
                errorMessage: nil
            )
        } catch is CancellationError {
            return SourceResult(tracks: [], errorMessage: nil)
        } catch {
            return SourceResult(tracks: [], errorMessage: error.localizedDescription)
        }
    }

    private func isCurrentSearch(_ generation: Int, keyword: String) -> Bool {
        generation == searchGeneration
            && activeSearchKeyword == keyword
            && query.trimmingCharacters(in: .whitespacesAndNewlines) == keyword
    }

    private func finishSearch(
        _ tracks: [Track],
        errorMessage: String?,
        generation: Int,
        keyword: String
    ) {
        guard isCurrentSearch(generation, keyword: keyword) else { return }
        results = tracks
        self.errorMessage = errorMessage
        isLoading = false
        hasSearched = true
        activeSearchKeyword = nil
    }
}
