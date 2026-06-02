import Foundation

/// Fetches scores & schedule from ESPN's free scoreboard endpoint.
///
/// One endpoint shape serves every team sport — only the sport/league path
/// segment changes (the spec's "one parser, league param"). We fetch the raw
/// JSON, decode just the fields we need via the private `ESPN*` types below,
/// and map them into our clean `Game` model.
@MainActor
final class SportsAPIService {

    /// The leagues FanRelay supports, each carrying its ESPN path segment.
    enum League: String, CaseIterable, Identifiable {
        case nfl, nba, mlb, nhl
        case collegeFootball
        case collegeBasketball
        case worldCup

        var id: String { rawValue }

        /// The "sport/league" portion of the ESPN URL.
        var espnPath: String {
            switch self {
            case .nfl:               return "football/nfl"
            case .nba:               return "basketball/nba"
            case .mlb:               return "baseball/mlb"
            case .nhl:               return "hockey/nhl"
            case .collegeFootball:   return "football/college-football"
            case .collegeBasketball: return "basketball/mens-college-basketball"
            case .worldCup:          return "soccer/fifa.world"
            }
        }

        var displayName: String {
            switch self {
            case .nfl: return "NFL"
            case .nba: return "NBA"
            case .mlb: return "MLB"
            case .nhl: return "NHL"
            case .collegeFootball: return "College Football"
            case .collegeBasketball: return "College Basketball"
            case .worldCup: return "World Cup"
            }
        }
    }

    enum ServiceError: LocalizedError {
        case badURL
        case badResponse(Int)
        case decoding(Error)

        var errorDescription: String? {
            switch self {
            case .badURL: return "Couldn’t build the request."
            case .badResponse(let code): return "Server returned an error (\(code))."
            case .decoding: return "Couldn’t read the scores data."
            }
        }
    }

    private let base = "https://site.api.espn.com/apis/site/v2/sports"

    /// Fetch the current scoreboard for a league and map it to `Game`s.
    func fetchScoreboard(for league: League) async throws -> [Game] {
        guard let url = URL(string: "\(base)/\(league.espnPath)/scoreboard") else {
            throw ServiceError.badURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else {
            throw ServiceError.badResponse(-1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw ServiceError.badResponse(http.statusCode)
        }

        do {
            let decoded = try JSONDecoder().decode(ESPNScoreboard.self, from: data)
            return decoded.events.compactMap { Self.makeGame(from: $0) }
        } catch {
            throw ServiceError.decoding(error)
        }
    }

    // MARK: - Map ESPN types → our Game

    /// ESPN sends times like "2026-06-01T22:40Z" — note: hours and minutes,
    /// usually NO seconds. ISO8601DateFormatter requires seconds, so we use a
    /// DateFormatter and try the formats ESPN actually uses, no-seconds first.
    private static func parseDate(_ string: String) -> Date? {
        let formats = [
            "yyyy-MM-dd'T'HH:mm'Z'",      // 2026-06-01T22:40Z   (what MLB sends)
            "yyyy-MM-dd'T'HH:mm:ss'Z'",   // with seconds, just in case
            "yyyy-MM-dd'T'HH:mmZ",        // with a numeric offset
            "yyyy-MM-dd'T'HH:mm:ssZ"
        ]
        for format in formats {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")   // stable, locale-independent
            f.timeZone = TimeZone(identifier: "UTC")        // the trailing Z means UTC
            f.dateFormat = format
            if let date = f.date(from: string) { return date }
        }
        return nil
    }

    private static func makeGame(from event: ESPNEvent) -> Game? {
        guard let comp = event.competitions.first,
              comp.competitors.count >= 2 else { return nil }

        // ESPN lists competitors with a homeAway flag rather than a fixed order.
        guard let homeRaw = comp.competitors.first(where: { $0.homeAway == "home" }),
              let awayRaw = comp.competitors.first(where: { $0.homeAway == "away" }) else {
            return nil
        }

        let date = parseDate(event.date) ?? Date()
        let state = GameState(fromESPN: comp.status.type.state)

        return Game(
            id: event.id,
            date: date,
            homeTeam: makeTeam(from: homeRaw),
            awayTeam: makeTeam(from: awayRaw),
            state: state,
            statusDetail: comp.status.type.shortDetail ?? comp.status.type.detail ?? ""
        )
    }

    private static func makeTeam(from c: ESPNCompetitor) -> GameTeam {
        GameTeam(
            id: c.team.id,
            displayName: c.team.displayName,
            abbreviation: c.team.abbreviation,
            logoURL: c.team.logo.flatMap(URL.init(string:)),
            score: c.score,
            isWinner: c.winner ?? false
        )
    }
}

// MARK: - Private ESPN decoding types
// These mirror only the slice of ESPN's JSON we need. Field names match the
// feed exactly; everything else in the payload is ignored by JSONDecoder.

private struct ESPNScoreboard: Decodable {
    let events: [ESPNEvent]
}

private struct ESPNEvent: Decodable {
    let id: String
    let date: String
    let competitions: [ESPNCompetition]
}

private struct ESPNCompetition: Decodable {
    let competitors: [ESPNCompetitor]
    let status: ESPNStatus
}

private struct ESPNCompetitor: Decodable {
    let homeAway: String
    let score: String?
    let winner: Bool?
    let team: ESPNTeam
}

private struct ESPNTeam: Decodable {
    let id: String
    let displayName: String
    let abbreviation: String
    let logo: String?
}

private struct ESPNStatus: Decodable {
    let type: ESPNStatusType
}

private struct ESPNStatusType: Decodable {
    let state: String?         // "pre" | "in" | "post"
    let detail: String?
    let shortDetail: String?
}
