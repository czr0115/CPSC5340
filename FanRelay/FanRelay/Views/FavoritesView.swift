import SwiftUI

/// The "pick your leagues" screen.
///
/// Shows every supported league with a checkmark for the ones you follow.
/// Tapping toggles the choice in the shared `FavoritesStore` (which persists
/// immediately). Used both at first launch (onboarding into the app) and later
/// from Settings to change picks.
struct FavoritesView: View {

    @EnvironmentObject private var favorites: FavoritesStore

    /// Called when the user taps Continue (first-run flow). In Settings this
    /// can be left as the default no-op.
    var onDone: () -> Void = {}

    /// First-run shows a "Continue" button; Settings doesn't need it.
    var showsContinue: Bool = false

    var body: some View {
        List {
            Section {
                ForEach(SportsAPIService.League.allCases) { league in
                    Button {
                        favorites.toggle(league)
                    } label: {
                        HStack {
                            Text(league.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if favorites.isFollowing(league) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }
            } header: {
                Text("Choose the leagues you want to follow")
            } footer: {
                if !favorites.hasFavorites {
                    Text("Pick at least one to see scores, news, and chat.")
                }
            }
        }
        .navigationTitle("Favorites")
        .toolbar {
            if showsContinue {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Continue", action: onDone)
                        .disabled(!favorites.hasFavorites)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        FavoritesView(showsContinue: true)
            .environmentObject(FavoritesStore())
    }
}
