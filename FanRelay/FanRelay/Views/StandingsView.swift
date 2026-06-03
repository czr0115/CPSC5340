import SwiftUI

/// Standings for a league, grouped by conference/division, with each team's
/// rank, logo, name, and record.
struct StandingsView: View {

    @StateObject private var vm: StandingsViewModel

    init(league: SportsAPIService.League) {
        _vm = StateObject(wrappedValue: StandingsViewModel(league: league))
    }

    var body: some View {
        Group {
            switch vm.state {
            case .loading:
                ProgressView("Loading standings…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty:
                ContentUnavailableView("No standings",
                                       systemImage: "list.number",
                                       description: Text("Standings aren’t available for \(vm.league.displayName)."))
            case .failed(let message):
                errorState(message)
            case .loaded:
                standingsList
            }
        }
        .navigationTitle("\(vm.league.displayName) Standings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
    }

    private var standingsList: some View {
        List {
            ForEach(vm.groupedStandings, id: \.group) { section in
                Section(section.group) {
                    ForEach(section.teams) { team in
                        HStack(spacing: 12) {
                            Text("\(team.rank)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .trailing)
                            AsyncImage(url: team.logoURL) { image in
                                image.resizable().scaledToFit()
                            } placeholder: {
                                Image(systemName: "sportscourt").foregroundStyle(.secondary)
                            }
                            .frame(width: 24, height: 24)
                            Text(team.teamName)
                                .font(.subheadline)
                            Spacer()
                            Text(team.record)
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await vm.load() }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.largeTitle).foregroundStyle(.secondary)
            Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Try Again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
        }
        .padding().frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NavigationStack {
        StandingsView(league: .nfl)
    }
}
