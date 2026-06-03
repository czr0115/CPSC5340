import SwiftUI

/// Settings: profile, identity backup, favorites, and a key reset. Publishing a
/// profile here lights up names + avatars across chat and discovery.
struct SettingsView: View {

    @StateObject private var vm: SettingsViewModel
    @EnvironmentObject private var favorites: FavoritesStore

    // Local UI state for the reveal/reset flows.
    @State private var revealedNsec: String?
    @State private var showResetConfirm = false
    /// Set true when the user resets identity; the parent watches this to route
    /// back to onboarding.
    @Binding var didResetIdentity: Bool

    init(service: NostrService, didResetIdentity: Binding<Bool>) {
        _vm = StateObject(wrappedValue: SettingsViewModel(service: service))
        _didResetIdentity = didResetIdentity
    }

    var body: some View {
        Form {
            profileSection
            favoritesSection
            relaysSection
            identitySection
            dangerSection
        }
        .navigationTitle("Settings")
    }

    // MARK: - Profile

    private var profileSection: some View {
        Section {
            TextField("Display name", text: $vm.displayName)
                .textInputAutocapitalization(.words)
            TextField("Picture URL (optional)", text: $vm.pictureURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
            Button("Save profile") { vm.saveProfile() }
                .disabled(!vm.canSave)
            if let confirm = vm.saveConfirmation {
                Label(confirm, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            }
        } header: {
            Text("Profile")
        } footer: {
            Text("Your name and picture appear in chat and to other fans. Published to relays as a public Nostr profile.")
        }
    }

    // MARK: - Favorites

    private var favoritesSection: some View {
        Section("Favorites") {
            NavigationLink {
                FavoritesView()   // no Continue button — just an editor here
            } label: {
                HStack {
                    Text("Followed leagues")
                    Spacer()
                    Text("\(favorites.followed.count)")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Relays

    private var relaysSection: some View {
        Section {
            ForEach(vm.relays, id: \.self) { relay in
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(.secondary)
                    Text(relay)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
            }
        } header: {
            Text("Relays")
        } footer: {
            Text("FanRelay reads and writes your social activity through these Nostr relays.")
        }
    }

    // MARK: - Identity (npub + nsec backup)

    private var identitySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Public key (npub)").font(.caption).foregroundStyle(.secondary)
                Text(vm.npub.isEmpty ? "—" : vm.npub)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            }

            if let nsec = revealedNsec {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Secret key (nsec)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                    Text(nsec)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                }
            } else {
                Button("Reveal secret key for backup") {
                    revealedNsec = vm.revealNsec()
                }
            }
        } header: {
            Text("Identity")
        } footer: {
            Text("Your nsec is the only way to recover this identity. Anyone who has it controls your account. Back it up somewhere safe and never share it.")
        }
    }

    // MARK: - Danger zone

    private var dangerSection: some View {
        Section {
            Button(role: .destructive) {
                showResetConfirm = true
            } label: {
                Text("Reset identity")
            }
        } footer: {
            Text("Deletes your key from this device. Without a backup of your nsec, this identity is gone for good.")
        }
        .confirmationDialog("Reset identity?",
                            isPresented: $showResetConfirm,
                            titleVisibility: .visible) {
            Button("Delete my key", role: .destructive) {
                vm.resetIdentity()
                didResetIdentity = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This can’t be undone unless you’ve backed up your nsec.")
        }
    }
}
