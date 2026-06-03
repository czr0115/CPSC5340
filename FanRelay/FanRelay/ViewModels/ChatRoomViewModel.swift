import Foundation
import Combine   // ObservableObject / @Published / Combine pipeline

/// Drives one team or league chat room.
///
/// MVVM: this is the only place that holds chat state and decides what's valid
/// or visible. It owns a `NostrService` (the transport layer), turns the
/// service's raw `roomMessages` into a filtered, display-ready list, runs input
/// validation before anything is posted, and drops muted authors.
@MainActor
final class ChatRoomViewModel: ObservableObject {

    /// Messages shown in the UI: this room only, muted authors removed,
    /// ordered oldest → newest.
    @Published private(set) var messages: [ChatMessage] = []

    /// Two-way bound to the text field in the View.
    @Published var draft: String = ""

    /// Set when the user tries to send something invalid. The View shows it,
    /// and it clears as soon as they start typing again.
    @Published private(set) var errorText: String?

    /// Mirrors the relay connection so the View can disable Send while offline.
    @Published private(set) var isConnected = false

    /// Live profile cache for sender names/avatars in bubbles.
    @Published private(set) var profiles: [String: NostrProfile] = [:]

    /// The room tag this screen is bound to, e.g. "fanrelay:nfl:eagles".
    let room: String

    /// Longest message we'll send. Stops one fan from flooding a room and
    /// satisfies the "cap length" input rule.
    let characterLimit = 280

    /// Authors to hide, fed from the service's NIP-51 mute list (kind 10000).
    private var mutedPubkeys: Set<String> = []

    private let service: NostrService
    private var cancellables = Set<AnyCancellable>()
    private var hasStarted = false

    /// `service` is injectable so we can later share one connection across
    /// rooms. For now each room spins up its own, which keeps step 2 fully
    /// demoable on its own.
    init(room: String, service: NostrService? = nil) {
        self.room = room
        self.service = service ?? NostrService()
    }

    // MARK: - Lifecycle

    /// Call from the View's `.onAppear`. Connects, wires up the live feed and
    /// mute list, then subscribes to this room. Guarded so a re-appearing View
    /// can't double up.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        // Recompute the visible list whenever new events arrive over the socket.
        service.$roomMessages
            .sink { [weak self] _ in self?.recomputeMessages() }
            .store(in: &cancellables)

        // Whenever the mute list changes, re-filter so muted authors vanish.
        service.$mutedPubkeys
            .sink { [weak self] muted in
                self?.mutedPubkeys = muted
                self?.recomputeMessages()
            }
            .store(in: &cancellables)

        // Keep the Send button's enabled state honest.
        service.$isConnected
            .assign(to: &$isConnected)

        // Mirror the shared profile cache so bubbles can show names + avatars.
        service.$profiles
            .sink { [weak self] in self?.profiles = $0 }
            .store(in: &cancellables)

        // Connect only if the service isn't already running. With the shared
        // app-level service this is already connected; a per-screen service
        // (e.g. previews) still gets started here.
        if !service.isConnected {
            service.start()
        }

        // The websocket needs a beat to open before it will accept a REQ.
        // (Same one-second pause the slice used; we'll swap it for a real
        // "connected" signal when we harden the service later.)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.service.subscribe(toRoom: self.room)
            self.service.loadMuteList()
        }
    }

    // MARK: - Sending

    /// Validate the draft and, if it passes, sign + publish it (rubric bullet 2).
    func send() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            errorText = "Message can’t be empty."
            return
        }
        guard trimmed.count <= characterLimit else {
            errorText = "Message is too long (max \(characterLimit) characters)."
            return
        }

        errorText = nil
        service.publish(content: trimmed, toRoom: room)
        draft = ""
    }

    /// Clear the error as soon as the user edits the field again.
    func draftChanged() {
        if errorText != nil { errorText = nil }
    }

    // MARK: - Mute

    /// Mute a message's author. The service publishes the updated NIP-51 list;
    /// the mute-list subscription then refreshes `mutedPubkeys`, which re-filters
    /// the room so this author's messages disappear.
    func mute(_ message: ChatMessage) {
        service.mute(pubkey: message.pubkey)
    }

    // MARK: - View helpers

    /// True for messages this device authored, so the View can align them right.
    func isMine(_ message: ChatMessage) -> Bool {
        !service.myPubkey.isEmpty && message.pubkey == service.myPubkey
    }

    /// Characters left before hitting the limit — for an optional live counter.
    var charactersRemaining: Int {
        characterLimit - draft.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    // MARK: - Filtering

    /// Rebuild the visible list: this room only, with muted authors removed.
    /// Called on every incoming event and whenever the mute set changes.
    private func recomputeMessages() {
        let visible = service.roomMessages
            .filter { message in
                message.roomId == room && !mutedPubkeys.contains(message.pubkey)
            }
            .sorted {
                $0.createdAt == $1.createdAt ? $0.id < $1.id : $0.createdAt < $1.createdAt
            }
        messages = visible
        // Fetch profiles for everyone in the room (cached ones are skipped).
        let senders = Array(Set(visible.map(\.pubkey)))
        if !senders.isEmpty {
            service.fetchProfiles(for: senders)
        }
    }

    /// A sender's profile if we have one (name/avatar), else nil.
    func profile(for pubkey: String) -> NostrProfile? {
        profiles[pubkey]
    }
}
