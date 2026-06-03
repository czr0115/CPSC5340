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

    // Fan discovery (NIP-78, kind 30078): pubkeys following the league we're
    // currently browsing, mapped to the set of fanrelay tags they follow.
    @Published var discoveredFans: [String: Set<String>] = [:]

    // Profiles (kind 0): pubkey → profile metadata, cached as they arrive.
    @Published var profiles: [String: NostrProfile] = [:]

    private var session: URLSession?
    private var task: URLSessionWebSocketTask?
    private var privateKey: secp256k1.Signing.PrivateKey?
    private var pubkeyHex = ""

    private let relayURL = URL(string: "wss://relay.damus.io")!

    /// The relays this app connects to, for display in Settings. Read-only for
    /// now (single relay); editing would require reconnect/persistence logic.
    var activeRelays: [String] {
        [relayURL.absoluteString]
    }
    private let roomTag  = "fanrelay:test"      // deterministic room id
    private let subId    = "fanrelay-slice"

    // MARK: - Start (identity + socket + listen)

    func start() {
        // 1) Identity — load the persistent key from the Keychain. If none is
        //    stored yet (e.g. running this screen before onboarding), generate
        //    one and save it so the identity is stable across launches.
        do {
            let sk: secp256k1.Signing.PrivateKey
            if let stored = try KeychainService.loadSecretKey() {
                sk = try secp256k1.Signing.PrivateKey(dataRepresentation: Data(stored))
                append("🔑 loaded key from Keychain")
            } else {
                sk = try secp256k1.Signing.PrivateKey()
                try KeychainService.saveSecretKey([UInt8](sk.dataRepresentation))
                append("🔑 generated + saved new key")
            }
            privateKey = sk
            pubkeyHex = Data(sk.publicKey.xonly.bytes).hexString  // 32-byte x-only pubkey
            append("🔑 pubkey \(pubkeyHex.prefix(12))…")
        } catch {
            append("❌ key setup failed: \(error)")
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

    /// The user's public key as a NIP-19 `npub…` string for display.
    /// Empty if encoding fails or the key isn't loaded yet.
    var myNpub: String {
        guard let bytes = hexToBytes(pubkeyHex), !bytes.isEmpty else { return "" }
        return (try? NIP19.encodePublicKey(bytes)) ?? ""
    }

    /// The user's secret key as a NIP-19 `nsec…` string, read from the Keychain
    /// on demand for backup/export. Returns nil if unavailable. Handle with care.
    func exportNsec() -> String? {
        guard let secret = ((try? KeychainService.loadSecretKey()) ?? nil) else { return nil }
        return try? NIP19.encodeSecretKey(secret)
    }

    private func hexToBytes(_ hex: String) -> [UInt8]? {
        guard hex.count % 2 == 0 else { return nil }
        var bytes = [UInt8]()
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let next = hex.index(idx, offsetBy: 2)
            guard let b = UInt8(hex[idx..<next], radix: 16) else { return nil }
            bytes.append(b)
            idx = next
        }
        return bytes
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
        if kind == 30078 {
            applyAffiliationEvent(ev)
            return
        }
        if kind == 0 {
            applyProfileEvent(ev)
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
        // Oldest → newest, with id as a stable tiebreaker for same-second
        // timestamps (Nostr created_at is whole seconds, so ties are common).
        roomMessages.sort {
            $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt
        }
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

    // MARK: - Affiliation list (NIP-78 app-data, kind 30078)

    /// The `d` identifier that makes our affiliation list addressable/replaceable.
    /// Publishing again with the same `d` replaces the prior list rather than
    /// stacking duplicates — so updating teams just overwrites.
    private let affiliationD = "fanrelay-teams"

    /// Publish this user's followed leagues as a replaceable list, one `t` tag
    /// per league (e.g. ["t","fanrelay:nfl"]). This is what makes a user
    /// discoverable to other fans following the same league.
    ///
    /// `leagueTags` are the raw room-tag strings, e.g. "fanrelay:nfl".
    func publishAffiliation(leagueTags: [String]) {
        guard let task else { append("⚠️ not connected"); return }
        // The `d` tag (addressable identifier) plus one `t` tag per league.
        var tags: [[String]] = [["d", affiliationD]]
        tags.append(contentsOf: leagueTags.map { ["t", $0] })
        do {
            let event = try makeSignedEvent(kind: 30078, tags: tags, content: "")
            let wire = try wireMessage(["EVENT", event])
            Task {
                do { try await task.send(.string(wire)) }
                catch { self.append("❌ affiliation publish failed: \(error.localizedDescription)") }
            }
            append("📣 affiliation updated (\(leagueTags.count) leagues)")
        } catch {
            append("❌ affiliation build/sign failed: \(error)")
        }
    }

    /// Find other fans following a given league tag. Subscribes for kind-30078
    /// events carrying that `t` tag; each match flows through `ingestEvent` →
    /// `applyAffiliationEvent`, populating `discoveredFans`.
    func discoverFans(forLeagueTag tag: String, subscriptionId: String = "fanrelay-fans") {
        guard let task else { return }
        discoveredFans = [:]   // fresh search
        let filter: [String: Any] = ["kinds": [30078], "#t": [tag], "limit": 100]
        do {
            let wire = try wireMessage(["REQ", subscriptionId, filter])
            Task {
                do { try await task.send(.string(wire)) }
                catch { self.append("❌ fan discovery failed: \(error.localizedDescription)") }
            }
            append("👥 discovering fans of \(tag)")
        } catch {
            append("❌ fan discovery build failed: \(error)")
        }
    }

    /// Read a kind-30078 event's `t` tags and record which fanrelay leagues the
    /// author follows. Keyed by pubkey, so a fan appears once with all their
    /// followed leagues.
    private func applyAffiliationEvent(_ ev: [String: Any]) {
        guard
            let pubkey = ev["pubkey"] as? String,
            let tags = ev["tags"] as? [[String]]
        else { return }
        var leagues = Set<String>()
        for tag in tags where tag.first == "t" && tag.count > 1 {
            leagues.insert(tag[1])
        }
        guard !leagues.isEmpty else { return }
        discoveredFans[pubkey] = leagues
    }

    // MARK: - Profiles (kind 0)

    /// Fetch kind-0 profile metadata for a batch of pubkeys. Each profile that
    /// comes back flows through `ingestEvent` → `applyProfileEvent` and lands in
    /// the `profiles` cache. Skips pubkeys we already have to avoid re-querying.
    func fetchProfiles(for pubkeys: [String], subscriptionId: String = "fanrelay-profiles") {
        guard let task else { return }
        let needed = Array(Set(pubkeys)).filter { profiles[$0] == nil && !$0.isEmpty }
        guard !needed.isEmpty else { return }

        let filter: [String: Any] = ["kinds": [0], "authors": needed, "limit": needed.count]
        do {
            let wire = try wireMessage(["REQ", subscriptionId, filter])
            Task {
                do { try await task.send(.string(wire)) }
                catch { self.append("❌ profile fetch failed: \(error.localizedDescription)") }
            }
            append("👤 fetching \(needed.count) profile(s)")
        } catch {
            append("❌ profile fetch build failed: \(error)")
        }
    }

    /// Parse a kind-0 event's JSON content into a NostrProfile and cache it.
    /// Content looks like {"name":"…","picture":"…","display_name":"…"}.
    private func applyProfileEvent(_ ev: [String: Any]) {
        guard
            let pubkey = ev["pubkey"] as? String,
            let content = ev["content"] as? String,
            let data = content.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        // Prefer "display_name", fall back to "name".
        let name = (json["display_name"] as? String) ?? (json["name"] as? String)
        let avatar = (json["picture"] as? String).flatMap(URL.init)

        profiles[pubkey] = NostrProfile(
            pubkey: pubkey,
            displayName: name?.trimmingCharacters(in: .whitespacesAndNewlines),
            avatarURL: avatar
        )
        append("👤 profile: \(name ?? pubkey.prefix(8).description)")
    }

    /// Publish *this user's* kind-0 profile metadata (name + optional picture).
    /// Kind 0 is replaceable, so this overwrites any prior profile. Updates the
    /// local cache optimistically so the user's own name/avatar shows at once.
    func publishProfile(name: String, pictureURL: String?) {
        guard let task else { append("⚠️ not connected"); return }

        var meta: [String: String] = ["name": name]
        if let pictureURL, !pictureURL.isEmpty { meta["picture"] = pictureURL }

        guard
            let data = try? JSONSerialization.data(withJSONObject: meta),
            let content = String(data: data, encoding: .utf8)
        else { append("❌ profile encode failed"); return }

        do {
            let event = try makeSignedEvent(kind: 0, tags: [], content: content)
            let wire = try wireMessage(["EVENT", event])
            Task {
                do { try await task.send(.string(wire)) }
                catch { self.append("❌ profile publish failed: \(error.localizedDescription)") }
            }
            // Optimistic local update for our own pubkey.
            profiles[pubkeyHex] = NostrProfile(
                pubkey: pubkeyHex,
                displayName: name,
                avatarURL: pictureURL.flatMap(URL.init)
            )
            append("👤 published profile: \(name)")
        } catch {
            append("❌ profile build/sign failed: \(error)")
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
