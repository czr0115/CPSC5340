import Foundation
import Combine

/// Drives the scores screen for one league: fetches the scoreboard, holds the
/// games, and exposes a single load-state the view switches on.
///
/// MVVM: all the fetching and state logic lives here; the view just renders
/// whatever `state` it's handed.
@MainActor
final class ScoresViewModel: ObservableObject {

    /// One value the view switches on — keeps the three required UI states
    /// (loading / empty / error) explicit and mutually exclusive.
    enum LoadState: Equatable {
        case loading
        case loaded([Game])
        case empty
        case failed(String)
    }

    @Published private(set) var state: LoadState = .loading

    let league: SportsAPIService.League
    private let service = SportsAPIService()

    init(league: SportsAPIService.League) {
        self.league = league
    }

    /// Fetch (or refetch) the scoreboard. Called on appear and on pull-to-refresh.
    func load() async {
        state = .loading
        do {
            let games = try await service.fetchScoreboard(for: league)
            state = games.isEmpty ? .empty : .loaded(games)
        } catch {
            let message = (error as? SportsAPIService.ServiceError)?.errorDescription
                ?? "Something went wrong loading scores."
            state = .failed(message)
        }
    }
}
