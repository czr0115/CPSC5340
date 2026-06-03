import SwiftUI

/// The app's home screen: the leagues you follow, each a gateway to that
/// league's scores and fan chat.
///
/// Reads the shared `FavoritesStore` for what to show. Empty-favorites is a
/// real state here (you can unfollow everything from Settings), so it's handled.
struct HomeView: View {

    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var nostr: NostrService

    /// Flipped true when the user resets identity in Settings; FanRelayApp
    /// watches this to route back to onboarding.
    @Binding var didResetIdentity: Bool

    var body: some View {
        Group {
            if favorites.hasFavorites {
                feed
            } else {
                emptyState
            }
        }
        .navigationTitle("My Feed")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsView(service: nostr, didResetIdentity: $didResetIdentity)
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
    }

    // MARK: - Feed

    private var feed: some View {
        List {
            ForEach(favorites.followed) { league in
                Section(league.displayName) {
                    NavigationLink {
                        ScoresView(league: league)
                    } label: {
                        Label("Scores & Schedule", systemImage: "sportscourt")
                    }
                    NavigationLink {
                        StandingsView(league: league)
                    } label: {
                        Label("Standings", systemImage: "list.number")
                    }
                    NavigationLink {
                        ChatRoomView(room: roomTag(for: league), title: league.displayName, service: nostr)
                    } label: {
                        Label("Fan Chat", systemImage: "bubble.left.and.bubble.right")
                    }
                    NavigationLink {
                        NewsView(query: league.displayName, title: league.displayName)
                    } label: {
                        Label("News", systemImage: "newspaper")
                    }
                    NavigationLink {
                        DiscoveryView(leagueTag: roomTag(for: league),
                                      title: league.displayName,
                                      service: nostr)
                    } label: {
                        Label("Fans", systemImage: "person.2")
                    }
                }
            }
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No leagues yet", systemImage: "star")
        } description: {
            Text("Add leagues in Settings to see scores and chat here.")
        }
    }

    // MARK: - Helpers

    /// Build the chat room tag for a league, matching the tag scheme the chat
    /// room uses (e.g. "fanrelay:mlb").
    private func roomTag(for league: SportsAPIService.League) -> String {
        "fanrelay:\(league.rawValue)"
    }
}

#Preview {
    NavigationStack {
        HomeView(didResetIdentity: .constant(false))
            .environmentObject(FavoritesStore())
            .environmentObject(NostrService())
    }
}
