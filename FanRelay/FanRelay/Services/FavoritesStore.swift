import Foundation
import Combine

/// Remembers which leagues the user follows.
///
/// Persists locally in UserDefaults so the choice survives relaunches. It's an
/// ObservableObject and created once at the app level, then shared — so the
/// picker and the home feed always agree on the current favorites.
///
/// (The spec also calls for publishing favorites as a replaceable Nostr list
/// for fan discovery. That's a small add-on we can layer on top of this local
/// store when we build discovery — this stays the single source of truth.)
@MainActor
final class FavoritesStore: ObservableObject {

    /// The leagues the user follows, in a stable display order.
    @Published private(set) var followed: [SportsAPIService.League] = []

    private let defaultsKey = "fanrelay.followedLeagues"

    init() {
        load()
    }

    // MARK: - Queries

    func isFollowing(_ league: SportsAPIService.League) -> Bool {
        followed.contains(league)
    }

    var hasFavorites: Bool { !followed.isEmpty }

    // MARK: - Mutations

    /// Add or remove a league, then persist.
    func toggle(_ league: SportsAPIService.League) {
        if let idx = followed.firstIndex(of: league) {
            followed.remove(at: idx)
        } else {
            followed.append(league)
        }
        save()
    }

    // MARK: - Persistence

    private func save() {
        let ids = followed.map(\.rawValue)
        UserDefaults.standard.set(ids, forKey: defaultsKey)
    }

    private func load() {
        let ids = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        // Map saved ids back to League cases, dropping any that no longer exist.
        followed = ids.compactMap { SportsAPIService.League(rawValue: $0) }
    }
}
