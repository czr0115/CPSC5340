import Foundation
import Combine

/// Drives the standings screen for one league. Same explicit load-state pattern
/// as ScoresViewModel.
@MainActor
final class StandingsViewModel: ObservableObject {

    enum LoadState: Equatable {
        case loading
        case loaded([Standing])
        case empty
        case failed(String)
    }

    @Published private(set) var state: LoadState = .loading

    let league: SportsAPIService.League
    private let service = SportsAPIService()

    init(league: SportsAPIService.League) {
        self.league = league
    }

    /// Standings grouped by conference/division, in display order.
    var groupedStandings: [(group: String, teams: [Standing])] {
        guard case .loaded(let standings) = state else { return [] }
        // Preserve first-seen group order while grouping.
        var order: [String] = []
        var byGroup: [String: [Standing]] = [:]
        for s in standings {
            if byGroup[s.groupName] == nil { order.append(s.groupName) }
            byGroup[s.groupName, default: []].append(s)
        }
        return order.map { ($0, byGroup[$0] ?? []) }
    }

    func load() async {
        state = .loading
        do {
            let standings = try await service.fetchStandings(for: league)
            state = standings.isEmpty ? .empty : .loaded(standings)
        } catch {
            let message = (error as? SportsAPIService.ServiceError)?.errorDescription
                ?? "Something went wrong loading standings."
            state = .failed(message)
        }
    }
}
