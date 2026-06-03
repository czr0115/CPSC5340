import Foundation
import Combine

/// Drives the Settings screen: edit + publish your profile (kind 0), view your
/// npub, export your nsec for backup, and reset identity.
///
/// Uses the shared NostrService (injected) so publishing a profile updates the
/// same cache chat and discovery read from.
@MainActor
final class SettingsViewModel: ObservableObject {

    // Profile editing
    @Published var displayName: String = ""
    @Published var pictureURL: String = ""
    @Published private(set) var saveConfirmation: String?

    // Identity (read-only display)
    @Published private(set) var npub: String = ""

    private let service: NostrService

    /// Relays the app is connected to, for read-only display.
    var relays: [String] { service.activeRelays }

    init(service: NostrService) {
        self.service = service
        loadCurrent()
    }

    /// Prefill the fields from the cached profile for our own pubkey, if any.
    private func loadCurrent() {
        npub = service.myNpub
        if let mine = service.profiles[service.myPubkey] {
            displayName = mine.displayName ?? ""
            pictureURL = mine.avatarURL?.absoluteString ?? ""
        }
    }

    var canSave: Bool {
        !displayName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Publish the edited profile as a kind-0 event.
    func saveProfile() {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let pic = pictureURL.trimmingCharacters(in: .whitespacesAndNewlines)
        service.publishProfile(name: name, pictureURL: pic.isEmpty ? nil : pic)
        saveConfirmation = "Profile published"
        // Clear the confirmation after a moment.
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            saveConfirmation = nil
        }
    }

    /// The nsec for backup/export — read on demand, never stored in the VM.
    func revealNsec() -> String? {
        service.exportNsec()
    }

    /// Wipe the stored key. The caller handles routing back to onboarding.
    func resetIdentity() {
        try? KeychainService.deleteSecretKey()
    }
}
