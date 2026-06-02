import SwiftUI

@main
struct FanRelayApp: App {

    /// Does a Nostr key already exist in the Keychain? Drives the first gate:
    /// no key → onboarding.
    @State private var hasIdentity = KeychainService.hasSecretKey()

    /// One shared favorites store for the whole app.
    @StateObject private var favorites = FavoritesStore()

    var body: some Scene {
        WindowGroup {
            rootView
                .environmentObject(favorites)
        }
    }

    /// The launch flow as a three-way gate:
    ///   no identity            → Onboarding
    ///   identity, no favorites → Favorites picker (first run)
    ///   identity + favorites   → Home
    @ViewBuilder
    private var rootView: some View {
        if !hasIdentity {
            OnboardingView {
                hasIdentity = KeychainService.hasSecretKey()
            }
        } else if !favorites.hasFavorites {
            NavigationStack {
                FavoritesView(onDone: {
                    // Continue tapped — favorites are saved; this just dismisses
                    // the picker. Because `favorites.hasFavorites` is now true,
                    // the gate falls through to Home on the next render.
                }, showsContinue: true)
            }
        } else {
            NavigationStack {
                HomeView()
            }
        }
    }
}
