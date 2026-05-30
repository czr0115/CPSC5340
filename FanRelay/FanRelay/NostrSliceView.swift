import SwiftUI

/// Minimal test harness for the Nostr slice.
/// Set this as your app's root view (replace `ContentView()` in the App struct).
///
/// Definition of done: after it appears you should see the log print your npub,
/// "connecting", an `OK ... accepted=true` after you tap Send, and your own
/// message appear under "Room messages" (read back from the relay). That proves
/// the full path: connect → sign → publish → relay accept → subscribe → receive.
struct NostrSliceView: View {
    @StateObject private var nostr = NostrService()
    @State private var draft = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    TextField("message", text: $draft)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(send)
                    Button("Send", action: send)
                        .buttonStyle(.borderedProminent)
                        .disabled(!nostr.isConnected)
                }
                .padding(.horizontal)

                List {
                    Section("Room messages") {
                        if nostr.messages.isEmpty {
                            Text("nothing yet…").foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(nostr.messages.enumerated()), id: \.offset) { _, msg in
                                Text(msg)
                            }
                        }
                    }
                    Section("Log") {
                        ForEach(Array(nostr.log.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.caption).monospaced()
                        }
                    }
                }
            }
            .navigationTitle("Nostr Slice")
        }
        .onAppear {
            nostr.start()
            // Give the websocket a beat to connect, then subscribe.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                nostr.subscribeToRoom()
            }
        }
    }

    private func send() {
        nostr.sendTestMessage(draft)
        draft = ""
    }
}

#Preview {
    NostrSliceView()
}
