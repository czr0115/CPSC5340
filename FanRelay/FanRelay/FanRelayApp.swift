import SwiftUI

@main
struct FanRelayApp: App {

    /// Does a Nostr key already exist in the Keychain? Drives the first gate:
    /// no key → onboarding.
    @State private var hasIdentity = KeychainService.hasSecretKey()

    /// One shared favorites store for the whole app.
    @StateObject private var favorites = FavoritesStore()

    /// Whether the user has finished the first-run favorites step. Initialized
    /// true if they already had favorites (returning user), false for a fresh
    /// identity so the picker stays put until they tap Continue — picking a
    /// league no longer bounces them to Home mid-selection.
    @State private var hasCompletedFavorites = FavoritesStore().hasFavorites

    /// One shared Nostr service for the whole app — a single relay connection
    /// used by chat, fan discovery, and affiliation publishing. Started once on
    /// launch and injected everywhere via `.environmentObject`.
    @StateObject private var nostr = NostrService()

    /// Flipped by Settings when the user resets their identity; we re-check the
    /// Keychain and fall back to onboarding.
    @State private var didResetIdentity = false

    var body: some Scene {
        WindowGroup {
            rootView
                .environmentObject(favorites)
                .environmentObject(nostr)
                .task {
                    // Connect once when the app appears (identity + socket).
                    nostr.start()
                }
                .onChange(of: favorites.followed) { _, leagues in
                    // Whenever favorites change, republish the affiliation list
                    // so this user stays discoverable by the leagues they follow.
                    // Replaceable (same `d`), so it overwrites the prior list.
                    let tags = leagues.map { "fanrelay:\($0.rawValue)" }
                    nostr.publishAffiliation(leagueTags: tags)
                }
        }
    }

    /// The launch flow as a three-way gate:
    ///   no identity                  → Onboarding
    ///   identity, favorites unfinished → Favorites picker (first run)
    ///   identity + favorites done     → Home
    @ViewBuilder
    private var rootView: some View {
        if !hasIdentity {
            OnboardingView {
                hasIdentity = KeychainService.hasSecretKey()
                // A freshly created/imported identity hasn't done favorites yet.
                hasCompletedFavorites = favorites.hasFavorites
            }
        } else if !hasCompletedFavorites {
            NavigationStack {
                FavoritesView(onDone: {
                    // Continue tapped — only now do we leave the picker. Picking
                    // a league mid-selection no longer navigates away.
                    hasCompletedFavorites = true
                }, showsContinue: true)
            }
        } else {
            NavigationStack {
                HomeView(didResetIdentity: $didResetIdentity)
            }
            .onChange(of: didResetIdentity) { _, didReset in
                if didReset {
                    // Key was wiped — also clear favorites so the new identity
                    // starts truly fresh, then drop back to onboarding and re-gate.
                    favorites.clear()
                    hasIdentity = KeychainService.hasSecretKey()
                    hasCompletedFavorites = false
                    didResetIdentity = false
                }
            }
        }
    }
}
