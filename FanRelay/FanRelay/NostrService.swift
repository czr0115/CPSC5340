import Foundation
import Combine
import CryptoKit   // SHA-256 (built in)
import Security     // secure random (built in)
import secp256k1   // GigaBitcoin/secp256k1.swift (module: secp256k1)

/// FanRelay — Nostr slice (de-risk spike), dependency-light edition.
///
/// Talks NIP-01 straight over a websocket, no Nostr SDK:
///   • URLSessionWebSocketTask (Foundation) — the relay connection
///   • CryptoKit SHA-256                     — the event id
///   • secp256k1 (GigaBitcoin/secp256k1.swift) — the Schnorr signature
///
/// Proves the whole risky path: make a keypair → build + sign a kind-1 note
/// tagged to a room → publish → relay says OK → subscribe by that tag → read
/// the note back → surface OK / CLOSED / EOSE.
///
/// (Uses the secp256k1 library that ships in Damus. I still can't compile iOS
/// here, so if anything trips, paste the error and I'll fix.)
@MainActor
final class NostrService: ObservableObject {

    // UI watches these.
    @Published var messages: [String] = []   // notes read back from the room
    @Published var log: [String] = []         // human-readable event/relay log
    @Published var isConnected = false

    // Chat rooms (build step 2): full parsed messages, in chronological order.
    @Published var roomMessages: [ChatMessage] = []

    // Mute (NIP-51, kind 10000): pubkeys this user has muted.
    @Published var mutedPubkeys: Set<String> = []

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var privateKey: secp256k1.Signing.PrivateKey?
    private var pubkeyHex = ""

    private let relayURL = URL(string: "wss://relay.damus.io")!
    private let roomTag  = "fanrelay:test"      // deterministic room id
    private let subId    = "fanrelay-slice"

    // MARK: - Start (identity + socket + listen)

    func start() {
        // 1) Identity — ephemeral keypair for the spike (Keychain comes later).
        do {
            let sk = try secp256k1.Signing.PrivateKey()
            privateKey = sk
            pubkeyHex = Data(sk.publicKey.xonly.bytes).hexString  // 32-byte x-only pubkey
            append("🔑 pubkey \(pubkeyHex.prefix(12))…")
        } catch {
            append("❌ key generation failed: \(error)")
            return
        }

        // 2) Open the websocket to one relay (multi-relay pool comes later).
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: relayURL)
        self.session = session
        self.task = task
        task.resume()
        isConnected = true
        append("🔌 connecting → \(relayURL.absoluteString)")

        // 3) Listen for everything the relay sends back.
        listen()
    }

    /// The current user's public key (x-only hex). The ViewModel uses this to
    /// tell "my" messages from others'. Empty until `start()` has run.
    var myPubkey: String { pubkeyHex }

    // MARK: - Receive loop (async/await)

    private func listen() {
        Task { [weak self] in
            guard let self else { return }
            while let task = self.task {
                do {
                    let message = try await task.receive()
                    if case let .string(text) = message {
                        self.handleRelayMessage(text)
                    }
                } catch {
                    self.append("🔌 socket closed: \(error.localizedDescription)")
                    self.isConnected = false
                    break
                }
            }
        }
    }

    // MARK: - Publish (write side)

    func sendTestMessage(_ text: String) {
        // Input validation (rubric bullet 2): no empty messages.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { append("⚠️ empty message ignored"); return }
        guard let task else { append("⚠️ not connected"); return }

        do {
            let event = try makeSignedNote(content: trimmed, room: roomTag)
            let wire = try wireMessage(["EVENT", event])   // ["EVENT", {event}]
            Task {
                do { try await task.send(.string(wire)) }
                catch { self.append("❌ send failed: \(error.localizedDescription)") }
            }
            append("📤 sent \"\(trimmed)\"")
        } catch {
            append("❌ build/sign failed: \(error)")
        }
    }

    // MARK: - Subscribe (read side)

    func subscribeToRoom() {
        guard let task else { return }
        // ["REQ", subId, { "kinds":[1], "#t":[room], "limit":50 }]
        let filter: [String: Any] = ["kinds": [1], "#t": [roomTag], "limit": 50]
        do {
            let wire = try wireMessage(["REQ", subId, filter])
            Task {
                do { try await task.send(.string(wire)) }
                catch { self.append("❌ subscribe failed: \(error.localizedDescription)") }
            }
            append("👂 subscribed to #\(roomTag)")
        } catch {
            append("❌ subscribe build failed: \(error)")
        }
    }

    // MARK: - Chat rooms (build step 2)

    /// Subscribe to a specific room by its tag (e.g. "fanrelay:nfl:eagles").
    /// New notes for that room then flow in through `ingestEvent`, which turns
    /// each one into a `ChatMessage` appended to `roomMessages`.
    func subscribe(toRoom room: String, subscriptionId: String = "fanrelay-room") {
        guard let task else { append("⚠️ not connected"); return }
        let filter: [String: Any] = ["kinds": [1], "#t": [room], "limit": 50]
        do {
            let wire = try wireMessage(["REQ", subscriptionId, filter])
            Task {
                do { try await task.send(.string(wire)) }
                catch { self.append("❌ subscribe failed: \(error.localizedDescription)") }
            }
            append("👂 subscribed to #\(room)")
        } catch {
            append("❌ subscribe build failed: \(error)")
        }
    }

    /// Build, sign, and publish a kind-1 note to a specific room.
    /// Content rules (empty / length / trim) are enforced by the ViewModel;
    /// this method handles the signing + transport and reports any failure.
    func publish(content: String, toRoom room: String) {
        guard let task else { append("⚠️ not connected"); return }
        do {
            let event = try makeSignedNote(content: content, room: room)
            let wire = try wireMessage(["EVENT", event])
            Task {
                do { try await task.send(.string(wire)) }
                catch { self.append("❌ send failed: \(error.localizedDescription)") }
            }
            append("📤 posted to #\(room)")
        } catch {
            append("❌ build/sign failed: \(error)")
        }
    }

    /// Route an incoming NIP-01 event by kind: kind 1 → chat message,
    /// kind 10000 → this user's mute list. Other kinds are ignored for now.
    func ingestEvent(_ ev: [String: Any]) {
        let kind = ev["kind"] as? Int ?? -1

        if kind == 10000 {
            applyMuteEvent(ev)
            return
        }
        guard kind == 1 else { return }

        guard
            let id = ev["id"] as? String,
            let pubkey = ev["pubkey"] as? String,
            let content = ev["content"] as? String,
            let createdAtRaw = ev["created_at"] as? Int
        else { return }

        // Keep the slice's plain-text list + log working too.
        messages.append(content)
        append("📥 \(content)")

        guard !roomMessages.contains(where: { $0.id == id }) else { return }

        let message = ChatMessage(
            id: id,
            pubkey: pubkey,
            roomId: firstRoomTag(in: ev) ?? "",
            content: content,
            createdAt: Date(timeIntervalSince1970: TimeInterval(createdAtRaw)),
            sig: ev["sig"] as? String ?? ""
        )
        roomMessages.append(message)
        roomMessages.sort { $0.createdAt < $1.createdAt }   // oldest → newest
    }

    /// The room a note belongs to is the value of its first `t` tag
    /// (NIP-01 only indexes the first value of any tag).
    private func firstRoomTag(in ev: [String: Any]) -> String? {
        guard let tags = ev["tags"] as? [[String]] else { return nil }
        for tag in tags where tag.first == "t" && tag.count > 1 {
            return tag[1]
        }
        return nil
    }

    // MARK: - Mute list (NIP-51, kind 10000)

    /// Fetch this user's latest mute list. Replaceable, so `limit: 1` gives the
    /// current one; its `p` tags are parsed in `applyMuteEvent`.
    func loadMuteList() {
        guard let task else { return }
        let filter: [String: Any] = ["kinds": [10000], "authors": [pubkeyHex], "limit": 1]
        do {
            let wire = try wireMessage(["REQ", "fanrelay-mute", filter])
            Task {
                do { try await task.send(.string(wire)) }
                catch { self.append("❌ mute fetch failed: \(error.localizedDescription)") }
            }
            append("🔇 fetching mute list")
        } catch {
            append("❌ mute fetch build failed: \(error)")
        }
    }

    /// Add a pubkey to the mute list and publish the updated (replaceable) list.
    func mute(pubkey: String) {
        var set = mutedPubkeys
        set.insert(pubkey)
        publishMuteList(set)
    }

    /// Remove a pubkey and publish the updated list. (Used later from Settings.)
    func unmute(pubkey: String) {
        var set = mutedPubkeys
        set.remove(pubkey)
        publishMuteList(set)
    }

    /// Read a kind-10000 event's `p` tags into the muted set. Replaceable, so
    /// the newest one simply replaces what we had.
    private func applyMuteEvent(_ ev: [String: Any]) {
        guard let tags = ev["tags"] as? [[String]] else { return }
        var set = Set<String>()
        for tag in tags where tag.first == "p" && tag.count > 1 {
            set.insert(tag[1])
        }
        mutedPubkeys = set
        append("🔇 mute list loaded (\(set.count))")
    }

    /// Sign + publish the mute list as one kind-10000 event with one `p` tag
    /// per muted author. Updates the local set optimistically so the UI reacts
    /// immediately (the relay also echoes it back to the open mute subscription).
    private func publishMuteList(_ pubkeys: Set<String>) {
        guard let task else { append("⚠️ not connected"); return }
        let tags = pubkeys.map { ["p", $0] }
        do {
            let event = try makeSignedEvent(kind: 10000, tags: tags, content: "")
            let wire = try wireMessage(["EVENT", event])
            Task {
                do { try await task.send(.string(wire)) }
                catch { self.append("❌ mute publish failed: \(error.localizedDescription)") }
            }
            mutedPubkeys = pubkeys
            append("🔇 mute list updated (\(pubkeys.count))")
        } catch {
            append("❌ mute build/sign failed: \(error)")
        }
    }

    // MARK: - Build + sign a NIP-01 event

    /// kind-1 room note — a thin wrapper over the generic signer.
    private func makeSignedNote(content: String, room: String) throws -> [String: Any] {
        try makeSignedEvent(kind: 1, tags: [["t", room]], content: content)
    }

    /// Generic NIP-01 signer: id = SHA-256 of the canonical serialization,
    /// then a BIP-340 Schnorr signature over that id. Same crypto the slice
    /// proved; `kind` and `tags` are now parameters so chat notes (kind 1) and
    /// mute lists (kind 10000) share one code path.
    private func makeSignedEvent(kind: Int, tags: [[String]], content: String) throws -> [String: Any] {
        guard let sk = privateKey else { throw NostrError.noKey }
        let createdAt = Int(Date().timeIntervalSince1970)

        // id = sha256 of the canonical serialization [0,pubkey,created_at,kind,tags,content]
        let serialized = canonicalSerialization(pubkey: pubkeyHex,
                                                createdAt: createdAt,
                                                kind: kind,
                                                tags: tags,
                                                content: content)
        let idBytes = Array(SHA256.hash(data: Data(serialized.utf8)))
        let idHex = Data(idBytes).hexString

        // Schnorr-sign the 32-byte id (BIP-340) with secure random aux.
        // 0.12.x exposes Schnorr as a dedicated key type — derive it from the same secret.
        let schnorrKey = try secp256k1.Schnorr.PrivateKey(dataRepresentation: sk.dataRepresentation)
        var message = idBytes
        var aux = randomBytes(32)
        let sig = try schnorrKey.signature(message: &message, auxiliaryRand: &aux)
        let sigHex = Data(sig.dataRepresentation).hexString   // 64-byte BIP-340 signature

        return [
            "id": idHex,
            "pubkey": pubkeyHex,
            "created_at": createdAt,
            "kind": kind,
            "tags": tags,
            "content": content,
            "sig": sigHex
        ]
    }

    /// Exact NIP-01 serialization: compact JSON, no whitespace, specific escapes.
    private func canonicalSerialization(pubkey: String, createdAt: Int, kind: Int,
                                        tags: [[String]], content: String) -> String {
        let tagsJSON = "[" + tags.map { tag in
            "[" + tag.map { "\"\(escape($0))\"" }.joined(separator: ",") + "]"
        }.joined(separator: ",") + "]"
        return "[0,\"\(pubkey)\",\(createdAt),\(kind),\(tagsJSON),\"\(escape(content))\"]"
    }

    /// The 7 characters NIP-01 requires escaping; everything else verbatim UTF-8.
    private func escape(_ s: String) -> String {
        var out = ""
        for ch in s.unicodeScalars {
            switch ch {
            case "\"":      out += "\\\""
            case "\\":      out += "\\\\"
            case "\n":      out += "\\n"
            case "\r":      out += "\\r"
            case "\t":      out += "\\t"
            case "\u{08}":  out += "\\b"
            case "\u{0C}":  out += "\\f"
            default:        out.unicodeScalars.append(ch)
            }
        }
        return out
    }

    // MARK: - Handle incoming relay messages (NIP-01 EVENT / OK / CLOSED / EOSE / NOTICE)

    private func handleRelayMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let type = arr.first as? String else { return }

        switch type {
        case "EVENT":   // ["EVENT", subId, {event}]
            if arr.count >= 3, let ev = arr[2] as? [String: Any] {
                ingestEvent(ev)
            }
        case "OK":      // ["OK", id, accepted, message]
            let id = (arr.count > 1 ? arr[1] as? String : nil) ?? ""
            let accepted = (arr.count > 2 ? arr[2] as? Bool : nil) ?? false
            let msg = (arr.count > 3 ? arr[3] as? String : nil) ?? ""
            append("✅ OK id=\(id.prefix(8)) accepted=\(accepted) \(msg)")
        case "CLOSED":  // ["CLOSED", subId, message] — auth-required / rate-limited / restricted …
            append("🚪 CLOSED: \((arr.count > 2 ? arr[2] as? String : nil) ?? "")")
        case "EOSE":    // ["EOSE", subId]
            append("⏹️ end of stored events")
        case "NOTICE":  // ["NOTICE", message]
            append("📣 notice: \((arr.count > 1 ? arr[1] as? String : nil) ?? "")")
        default:
            break
        }
    }

    // MARK: - Helpers

    private func wireMessage(_ parts: [Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: parts, options: [])
        return String(decoding: data, as: UTF8.self)
    }

    private func randomBytes(_ n: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: n)
        _ = SecRandomCopyBytes(kSecRandomDefault, n, &bytes)
        return bytes
    }

    private func append(_ line: String) { log.append(line) }

    enum NostrError: Error { case noKey }
}

private extension Data {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}
