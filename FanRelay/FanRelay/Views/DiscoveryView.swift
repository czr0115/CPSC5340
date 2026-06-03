import SwiftUI

/// Fan discovery for one league: other users following the same league,
/// found via their published Nostr affiliation lists (kind 30078).
///
/// Reads the shared NostrService through its ViewModel. Pubkeys are shown in
/// short form for now — real names arrive when profiles (kind 0) land.
struct DiscoveryView: View {

    @StateObject private var vm: DiscoveryViewModel

    init(leagueTag: String, title: String, service: NostrService) {
        _vm = StateObject(wrappedValue:
            DiscoveryViewModel(leagueTag: leagueTag, title: title, service: service))
    }

    var body: some View {
        Group {
            switch vm.state {
            case .loading:
                ProgressView("Finding fans…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .empty:
                ContentUnavailableView {
                    Label("No other fans yet", systemImage: "person.2")
                } description: {
                    Text("No one else following \(vm.title) has shown up yet. As more fans join, they’ll appear here.")
                }
            case .loaded(let fans):
                list(fans)
            }
        }
        .navigationTitle("\(vm.title) Fans")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { vm.start() }
    }

    private func list(_ fans: [String]) -> some View {
        List(fans, id: \.self) { pubkey in
            let profile = vm.profile(for: pubkey)
            HStack(spacing: 12) {
                avatar(for: profile)
                VStack(alignment: .leading, spacing: 2) {
                    Text(profile?.name ?? shortPubkey(pubkey))
                        .font(.subheadline.weight(.medium))
                    if profile?.displayName != nil {
                        // Show the short pubkey underneath once we have a name,
                        // so the identity is still verifiable at a glance.
                        Text(shortPubkey(pubkey))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 2)
        }
        .listStyle(.plain)
    }

    /// Avatar from the profile's picture URL, with a person-icon fallback while
    /// loading, on failure, or when the profile has no picture.
    @ViewBuilder
    private func avatar(for profile: NostrProfile?) -> some View {
        let placeholder = Image(systemName: "person.crop.circle.fill")
            .font(.title2)
            .foregroundStyle(.secondary)

        if let url = profile?.avatarURL {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    placeholder
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(Circle())
        } else {
            placeholder.frame(width: 32, height: 32)
        }
    }

    /// Same short form chat uses: 8 leading … 6 trailing.
    private func shortPubkey(_ pubkey: String) -> String {
        guard pubkey.count > 14 else { return pubkey }
        return "\(pubkey.prefix(8))…\(pubkey.suffix(6))"
    }
}
