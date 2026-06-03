import Foundation

/// A Nostr profile (kind-0 metadata) for one pubkey.
///
/// Kind-0 events carry a JSON content blob like:
///   {"name":"nymfan","picture":"https://…/avatar.png","about":"…"}
/// We keep the fields the app actually shows: a display name and an avatar URL.
struct NostrProfile: Identifiable, Equatable {
    let pubkey: String              // hex pubkey — the stable identity
    let displayName: String?        // from "name" (or "display_name")
    let avatarURL: URL?             // from "picture"

    var id: String { pubkey }

    /// What the UI shows as the name: the profile name if set, otherwise a
    /// short form of the pubkey (8 leading … 6 trailing) — same as chat/discovery.
    var name: String {
        if let displayName, !displayName.isEmpty { return displayName }
        guard pubkey.count > 14 else { return pubkey }
        return "\(pubkey.prefix(8))…\(pubkey.suffix(6))"
    }
}
