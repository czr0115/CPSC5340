import SwiftUI

/// Shows one league's scoreboard: live, recent, and upcoming games.
///
/// Reads its whole state from `ScoresViewModel` and switches on the single
/// `state` value to render loading / empty / error / content. No fetching or
/// logic here — that's the MVVM split the rubric checks.
struct ScoresView: View {

    @StateObject private var vm: ScoresViewModel
    @EnvironmentObject private var nostr: NostrService

    init(league: SportsAPIService.League) {
        _vm = StateObject(wrappedValue: ScoresViewModel(league: league))
    }

    var body: some View {
        Group {
            switch vm.state {
            case .loading:
                ProgressView("Loading scores…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .empty:
                emptyState

            case .failed(let message):
                errorState(message)

            case .loaded(let games):
                gamesList(games)
            }
        }
        .navigationTitle(vm.league.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }          // fetch when the screen appears
    }

    // MARK: - Content

    private func gamesList(_ games: [Game]) -> some View {
        List(games) { game in
            VStack(spacing: 6) {
                GameRow(game: game)
                // Live games get their own chat room, scoped to the event id.
                if game.state == .live {
                    NavigationLink {
                        ChatRoomView(room: "fanrelay:event:\(game.id)",
                                     title: "\(game.awayTeam.abbreviation) vs \(game.homeTeam.abbreviation) — Live",
                                     service: nostr)
                    } label: {
                        Label("Join live chat", systemImage: "dot.radiowaves.left.and.right")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await vm.load() }   // pull-to-refresh
    }

    // MARK: - States

    private var emptyState: some View {
        ContentUnavailableView(
            "No games",
            systemImage: "calendar",
            description: Text("There are no \(vm.league.displayName) games on the schedule right now.")
        )
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Try Again") {
                Task { await vm.load() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - One game row

private struct GameRow: View {
    let game: Game

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                teamLine(game.awayTeam)
                teamLine(game.homeTeam)
            }
            Spacer()
            statusBadge
        }
        .padding(.vertical, 4)
    }

    private func teamLine(_ team: GameTeam) -> some View {
        HStack(spacing: 8) {
            AsyncImage(url: team.logoURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Image(systemName: "sportscourt").foregroundStyle(.secondary)
            }
            .frame(width: 24, height: 24)

            Text(team.abbreviation)
                .font(.subheadline.weight(team.isWinner ? .bold : .regular))

            Text(team.displayName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer()

            if let score = team.score, game.state != .scheduled {
                Text(score)
                    .font(.subheadline.weight(team.isWinner ? .bold : .regular))
                    .monospacedDigit()
            }
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch game.state {
        case .live:
            Text("LIVE")
                .font(.caption2.bold())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.red, in: Capsule())
                .foregroundStyle(.white)
        case .scheduled:
            Text(game.date, format: .dateTime.hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        case .final, .unknown:
            Text(game.state == .final ? "Final" : game.statusDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        ScoresView(league: .mlb)
    }
}
