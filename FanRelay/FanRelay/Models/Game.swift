import Foundation

/// A single game (or match) from the ESPN scoreboard.
///
/// ESPN's JSON is enormous — odds, betting links, weather, player leaders, and
/// much more. We decode only the handful of fields FanRelay needs and let the
/// rest fall away. The nesting we care about is:
///   events[] → competitions[0] → competitors[] (home + away) → team{} + score
///   events[] → competitions[0] → status.type   (scheduled / in / post)
struct Game: Identifiable, Equatable {
    let id: String              // ESPN event id
    let date: Date              // start time (UTC in the feed)
    let homeTeam: GameTeam
    let awayTeam: GameTeam
    let state: GameState        // pre / in / post
    let statusDetail: String    // human text e.g. "6/1 - 6:40 PM EDT" or "Final"

    /// Convenience for the UI: "DET @ TB" style.
    var shortMatchup: String { "\(awayTeam.abbreviation) @ \(homeTeam.abbreviation)" }
}

/// One side of a game. `score` is optional because scheduled games have "0"
/// or no meaningful score yet; we keep it as text since ESPN sends it as text.
struct GameTeam: Equatable {
    let id: String
    let displayName: String
    let abbreviation: String
    let logoURL: URL?
    let score: String?
    let isWinner: Bool
}

/// Simplified game state derived from ESPN's status.type.state ("pre"/"in"/"post").
enum GameState: String {
    case scheduled = "pre"
    case live      = "in"
    case final     = "post"
    case unknown

    init(fromESPN state: String?) {
        self = GameState(rawValue: state ?? "") ?? .unknown
    }
}
