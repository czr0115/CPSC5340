import Foundation
import Combine

/// Drives the fan-discovery screen for one league. Asks the shared NostrService
/// to find fans following a league tag, then exposes the results as a live,
/// self-excluded list of pubkeys.
///
/// The service is shared (one app-wide connection), so this VM doesn't own it —
/// it's injected and observed, the same pattern chat uses.
@MainActor
final class DiscoveryViewModel: ObservableObject {

    enum LoadState: Equatable {
        case loading
        case loaded([String])   // fan pubkeys (self excluded)
        case empty
    }

    @Published private(set) var state: LoadState = .loading

    /// Live profile cache from the shared service, for name/avatar lookup.
    @Published private(set) var profiles: [String: NostrProfile] = [:]

    let leagueTag: String   // e.g. "fanrelay:nfl"
    let title: String       // e.g. "NFL"

    private let service: NostrService
    private var cancellables = Set<AnyCancellable>()
    private var hasStarted = false

    init(leagueTag: String, title: String, service: NostrService) {
        self.leagueTag = leagueTag
        self.title = title
        self.service = service
    }

    /// Call from the View's `.onAppear`. Subscribes to live discovery results,
    /// then kicks off the query. Guarded against re-appearing views.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        // Recompute the visible list whenever new affiliation events arrive.
        service.$discoveredFans
            .sink { [weak self] fans in self?.recompute(from: fans) }
            .store(in: &cancellables)

        // Mirror the shared profile cache so rows can show names + avatars.
        service.$profiles
            .sink { [weak self] in self?.profiles = $0 }
            .store(in: &cancellables)

        // Give the socket a beat (same as chat), then ask for fans.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.service.discoverFans(forLeagueTag: self.leagueTag)
        }
    }

    /// A profile for a pubkey if we have one (name/avatar), else nil.
    func profile(for pubkey: String) -> NostrProfile? {
        profiles[pubkey]
    }

    /// Drop ourselves from the results so the screen reads as "other fans".
    /// The raw `discoveredFans` still holds everyone (handy for debugging/demo).
    private func recompute(from fans: [String: Set<String>]) {
        let me = service.myPubkey
        let others = fans.keys
            .filter { $0 != me }
            .sorted()
        state = others.isEmpty ? .empty : .loaded(others)
        // Pull profiles for the fans we're showing (cached ones are skipped).
        if !others.isEmpty {
            service.fetchProfiles(for: others)
        }
    }
}
