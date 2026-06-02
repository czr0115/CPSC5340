import Foundation
import Combine

/// Drives the news screen for one league/team query. Same explicit load-state
/// approach as ScoresViewModel — one value the view switches on.
@MainActor
final class NewsViewModel: ObservableObject {

    enum LoadState: Equatable {
        case loading
        case loaded([Article])
        case empty
        case failed(String)
    }

    @Published private(set) var state: LoadState = .loading

    let query: String     // what we search Google News for, e.g. "NFL"
    let title: String     // display name, e.g. "NFL"

    private let service = NewsService()

    init(query: String, title: String) {
        self.query = query
        self.title = title
    }

    func load() async {
        state = .loading
        do {
            let articles = try await service.fetchNews(query: query)
            state = articles.isEmpty ? .empty : .loaded(articles)
        } catch {
            let message = (error as? NewsService.ServiceError)?.errorDescription
                ?? "Something went wrong loading news."
            state = .failed(message)
        }
    }
}
