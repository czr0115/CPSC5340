import Foundation

/// One chat message in a FanRelay room.
///
/// This is a plain value type — a Swift mirror of the fields we care about
/// from a Nostr kind-1 event (NIP-01). `NostrService` builds one of these
/// from each incoming EVENT, so the ViewModel and View only ever deal with
/// `ChatMessage`, never the raw relay JSON.
struct ChatMessage: Identifiable, Equatable {

    /// The Nostr event id (64-char hex). It's unique per event, so it doubles
    /// as our `Identifiable` id for SwiftUI lists and as a dedup key.
    let id: String

    /// Author's public key (32-byte x-only hex). For now we show this
    /// directly; later it maps to a kind-0 profile display name.
    let pubkey: String

    /// The room this message belongs to — the value of the `t` tag,
    /// e.g. "fanrelay:nfl:eagles".
    let roomId: String

    /// The message text.
    let content: String

    /// When the author created it. Nostr sends this as Unix seconds; we keep
    /// a `Date` here so the View can format it easily.
    let createdAt: Date

    /// The 64-byte BIP-340 Schnorr signature (hex). We carry it so the model
    /// is a faithful record of the event, even though the relay already
    /// verified it before sending it to us.
    let sig: String

    /// A short, readable form of the pubkey for the UI until profiles land,
    /// e.g. "a1b2c3d4…7f8e9d".
    var shortPubkey: String {
        guard pubkey.count > 14 else { return pubkey }
        return "\(pubkey.prefix(8))…\(pubkey.suffix(6))"
    }
}
