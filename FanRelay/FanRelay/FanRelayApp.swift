import SwiftUI

@main
struct FanRelayApp: App {

    /// Whether a key already exists in the Keychain. Drives which screen shows
    /// at launch: an existing key → straight into the app; none → onboarding.
    /// `@State` so that finishing onboarding can flip it and swap the view.
    @State private var hasIdentity = KeychainService.hasSecretKey()

    var body: some Scene {
        WindowGroup {
            if hasIdentity {
                // Temporary root for now — one hardcoded room. This becomes the
                // real Home/feed screen in later build steps.
                NavigationStack {
                    ChatRoomView(room: "fanrelay:nfl:eagles")
                }
            } else {
                OnboardingView {
                    // Called when onboarding saves a key. Re-check the Keychain
                    // and flip into the app.
                    hasIdentity = KeychainService.hasSecretKey()
                }
            }
        }
    }
}
