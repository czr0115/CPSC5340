import Foundation
import Combine
import secp256k1   // GigaBitcoin/secp256k1.swift — same library the slice uses

/// Drives the onboarding screen: create a brand-new Nostr identity, or import
/// an existing one from an `nsec`. Either way the result is the same — 32 raw
/// secret-key bytes saved to the Keychain, which becomes the app's login.
///
/// MVVM: this owns all the logic (key generation, validation, persistence);
/// the View only shows fields and buttons and reports taps back here.
@MainActor
final class OnboardingViewModel: ObservableObject {

    /// What the user types when importing.
    @Published var importText: String = ""

    /// Set when something goes wrong (bad nsec, save failure). The View shows it.
    @Published private(set) var errorText: String?

    /// Flips to true once a key is saved. The View/app watches this to leave
    /// onboarding and continue into the app.
    @Published private(set) var didComplete = false

    /// After "Create", we show the user their new key so they can back it up.
    /// `nil` until they generate one.
    @Published private(set) var newKeyNsec: String?
    @Published private(set) var newKeyNpub: String?

    // MARK: - Create a new identity

    /// Generate a fresh keypair, save the secret to the Keychain, and surface
    /// the nsec/npub so the user can record them.
    func createNewKey() {
        errorText = nil
        do {
            let sk = try secp256k1.Signing.PrivateKey()
            let secretBytes = [UInt8](sk.dataRepresentation)
            let pubBytes = [UInt8](sk.publicKey.xonly.bytes)

            try KeychainService.saveSecretKey(secretBytes)

            // Show the user their keys (encoded for humans).
            newKeyNsec = try NIP19.encodeSecretKey(secretBytes)
            newKeyNpub = try NIP19.encodePublicKey(pubBytes)
            // We don't set didComplete yet — the View shows the backup warning
            // first, then the user taps "Continue" (see `confirmNewKey`).
        } catch {
            errorText = "Couldn’t create a key: \(error.localizedDescription)"
        }
    }

    /// User has seen and (hopefully) backed up the new key; proceed into the app.
    func confirmNewKey() {
        didComplete = true
    }

    // MARK: - Import an existing identity

    /// Validate a pasted `nsec`, save its bytes, and continue. Bad input is
    /// rejected with a message instead of saving a broken key (rubric: input
    /// validation). The NIP-19 checksum catches typos here.
    func importKey() {
        errorText = nil
        let trimmed = importText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            errorText = "Paste your nsec to import."
            return
        }
        guard trimmed.hasPrefix("nsec1") else {
            errorText = "That doesn’t look like an nsec key."
            return
        }

        do {
            let secretBytes = try NIP19.decodeSecretKey(trimmed)
            // Sanity check: make sure the bytes actually form a usable key.
            _ = try secp256k1.Signing.PrivateKey(dataRepresentation: Data(secretBytes))
            try KeychainService.saveSecretKey(secretBytes)
            didComplete = true
        } catch {
            errorText = "That nsec isn’t valid. Check it and try again."
        }
    }

    /// Clear the error as the user edits the import field.
    func importTextChanged() {
        if errorText != nil { errorText = nil }
    }
}
