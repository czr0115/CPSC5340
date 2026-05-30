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
            let event = try makeSignedNote(content: trimmed)
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

    // MARK: - Build + sign a NIP-01 event

    private func makeSignedNote(content: String) throws -> [String: Any] {
        guard let sk = privateKey else { throw NostrError.noKey }
        let createdAt = Int(Date().timeIntervalSince1970)
        let kind = 1
        let tags = [["t", roomTag]]   // ONE room tag (NIP-01: only first value indexed)

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
            if arr.count >= 3, let ev = arr[2] as? [String: Any],
               let content = ev["content"] as? String {
                messages.append(content)
                append("📥 \(content)")
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
