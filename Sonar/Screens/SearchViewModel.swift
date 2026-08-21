import Observation

@MainActor
@Observable
final class SearchViewModel {
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

        do {
            let primary = try await runtime.search(keyword, source: .wy, page: 1).list
            guard isCurrentSearch(generation, keyword: keyword) else { return }
            if !primary.isEmpty {
                finishSearch(primary, errorMessage: nil, generation: generation, keyword: keyword)
                return
            }
            do {
                let fallback = try await runtime.search(keyword, source: .tx, page: 1).list
                finishSearch(fallback, errorMessage: nil, generation: generation, keyword: keyword)
            } catch {
                finishSearch(
                    [],
                    errorMessage: "搜索失败：\(error.localizedDescription)",
                    generation: generation,
                    keyword: keyword
                )
            }
        } catch {
            let primaryFailure = error.localizedDescription
            guard isCurrentSearch(generation, keyword: keyword) else { return }
            do {
                let fallback = try await runtime.search(keyword, source: .tx, page: 1).list
                finishSearch(
                    fallback,
                    errorMessage: fallback.isEmpty
                        ? "未找到结果；首选渠道 \(primaryFailure)"
                        : nil,
                    generation: generation,
                    keyword: keyword
                )
            } catch {
                finishSearch(
                    [],
                    errorMessage: "搜索失败：首选渠道 \(primaryFailure)；备用渠道 \(error.localizedDescription)",
                    generation: generation,
                    keyword: keyword
                )
            }
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
