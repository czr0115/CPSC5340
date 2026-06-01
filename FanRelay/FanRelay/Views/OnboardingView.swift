import SwiftUI

/// The login / identity screen — the first thing a new user sees.
///
/// Two paths: create a brand-new Nostr key, or import an existing `nsec`.
/// All logic lives in `OnboardingViewModel`; this view only presents it.
/// When `vm.didComplete` flips true, the parent (FanRelayApp) swaps this out
/// for the main app.
struct OnboardingView: View {

    @StateObject private var vm = OnboardingViewModel()

    /// The app passes this in so onboarding can tell it "I'm done."
    var onComplete: () -> Void = {}

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header

                    if let nsec = vm.newKeyNsec {
                        newKeyBackup(nsec: nsec, npub: vm.newKeyNpub ?? "")
                    } else {
                        createSection
                        Divider()
                        importSection
                    }

                    if let error = vm.errorText {
                        Text(error)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
            .navigationTitle("FanRelay")
            .onChange(of: vm.didComplete) { _, done in
                if done { onComplete() }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "sportscourt")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Your teams, on Nostr.")
                .font(.title2).bold()
            Text("FanRelay uses a Nostr key as your login. No email, no password.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 20)
    }

    // MARK: - Create

    private var createSection: some View {
        VStack(spacing: 12) {
            Text("New here?")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                vm.createNewKey()
            } label: {
                Text("Create a new key")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    // MARK: - Import

    private var importSection: some View {
        VStack(spacing: 12) {
            Text("Already have a Nostr key?")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            TextField("Paste your nsec…", text: $vm.importText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: vm.importText) { _, _ in vm.importTextChanged() }
            Button {
                vm.importKey()
            } label: {
                Text("Import key")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    // MARK: - New-key backup (shown after Create)

    private func newKeyBackup(nsec: String, npub: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Save your secret key", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text("This nsec is the only way back into your account. There's no reset and no recovery — if you lose it, it's gone. Copy it somewhere safe before continuing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            keyBox(title: "Secret key (nsec)", value: nsec, isSecret: true)
            keyBox(title: "Public key (npub)", value: npub, isSecret: false)

            Button {
                vm.confirmNewKey()
            } label: {
                Text("I’ve saved it — continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private func keyBox(title: String, value: String, isSecret: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(value)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2)
                Spacer()
                Button {
                    UIPasteboard.general.string = value
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
            }
            .padding(10)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

#Preview {
    OnboardingView()
}
