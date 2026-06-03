import Foundation

/// One team's standing within a conference/group: where they sit and their
/// record. Built from ESPN's standings endpoint.
struct Standing: Identifiable, Equatable {
    let id: String          // team id
    let rank: Int           // playoff seed / position within the group
    let teamName: String
    let teamAbbreviation: String
    let logoURL: URL?
    let record: String      // overall record, e.g. "14-3"

    /// Section this team belongs to (e.g. "AFC", "NFC") for grouped display.
    let groupName: String
}
