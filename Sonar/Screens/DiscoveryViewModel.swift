import Foundation
import Observation

struct DiscoveryPageState: Sendable {
    var items: [PlaylistSummary] = []
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    var loadMoreError: String?
    var page = 0
    var hasMore = true
}

@MainActor
@Observable
final class DiscoveryViewModel {
    private let runtime: SourceRuntime
    private(set) var pages: [MusicSource: DiscoveryPageState] = [:]
    private(set) var selectedCategories: [MusicSource: PlaylistCategory] = [:]
    private var generations: [MusicSource: Int] = [:]

    init(runtime: SourceRuntime) {
        self.runtime = runtime
        for source in MusicSource.allCases {
            pages[source] = DiscoveryPageState()
            selectedCategories[source] = source.playlistCategories[0]
            generations[source] = 0
        }
    }

    func state(for source: MusicSource) -> DiscoveryPageState {
        pages[source] ?? DiscoveryPageState()
    }

    func selectedCategory(for source: MusicSource) -> PlaylistCategory {
        selectedCategories[source] ?? source.playlistCategories[0]
    }

    func loadInitial(for source: MusicSource) async {
        var state = state(for: source)
        guard state.items.isEmpty, !state.isLoading else { return }
        let generation = generations[source, default: 0]
        state.isLoading = true
        state.errorMessage = nil
        pages[source] = state

        do {
            let category = selectedCategory(for: source)
            let page = try await runtime.playlistCatalog(
                source: source,
                sortId: category.id,
                tagId: nil,
                page: 1
            )
            guard generations[source] == generation else { return }
            state.items = page.list
            state.page = page.page
            state.hasMore = !page.list.isEmpty
        } catch is CancellationError {
            state.isLoading = false
            pages[source] = state
            return
        } catch {
            state.errorMessage = error.localizedDescription
        }
        state.isLoading = false
        pages[source] = state
    }

    func refresh(_ source: MusicSource) async {
        generations[source, default: 0] += 1
        pages[source] = DiscoveryPageState()
        await loadInitial(for: source)
    }

    func selectCategory(_ category: PlaylistCategory, for source: MusicSource) async {
        guard selectedCategory(for: source) != category else { return }
        selectedCategories[source] = category
        await refresh(source)
    }

    func loadMore(for source: MusicSource) async {
        var state = state(for: source)
        guard !state.items.isEmpty,
              state.hasMore,
              !state.isLoading,
              !state.isLoadingMore else { return }

        let generation = generations[source, default: 0]
        let nextPage = state.page + 1
        state.isLoadingMore = true
        state.loadMoreError = nil
        pages[source] = state

        do {
            let category = selectedCategory(for: source)
            let page = try await runtime.playlistCatalog(
                source: source,
                sortId: category.id,
                tagId: nil,
                page: nextPage
            )
            guard generations[source] == generation else { return }
            let existingKeys = Set(state.items.map(\.key))
            let additions = page.list.filter { !existingKeys.contains($0.key) }
            state.items.append(contentsOf: additions)
            state.page = page.page
            state.hasMore = !page.list.isEmpty && !additions.isEmpty
        } catch is CancellationError {
            state.isLoadingMore = false
            pages[source] = state
            return
        } catch {
            guard generations[source] == generation else { return }
            state.loadMoreError = error.localizedDescription
        }
        state.isLoadingMore = false
        pages[source] = state
    }
}
