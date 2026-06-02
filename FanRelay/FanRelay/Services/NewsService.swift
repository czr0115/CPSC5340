import Foundation

/// Fetches team/league news from Google News RSS.
///
/// The feed is XML, so we can't use Codable. Foundation's `XMLParser` is
/// event-driven (it calls us back as it walks the document), so the parsing
/// lives in a small delegate class below. The service builds the query URL,
/// fetches, parses, and hands back clean `Article` values.
@MainActor
final class NewsService {

    enum ServiceError: LocalizedError {
        case badURL
        case badResponse(Int)
        case parsing

        var errorDescription: String? {
            switch self {
            case .badURL: return "Couldn’t build the news request."
            case .badResponse(let code): return "News server error (\(code))."
            case .parsing: return "Couldn’t read the news feed."
            }
        }
    }

    /// Fetch news for a free-text query (a league or team name).
    func fetchNews(query: String) async throws -> [Article] {
        // Google News RSS search endpoint, scoped to US English.
        var components = URLComponents(string: "https://news.google.com/rss/search")
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "hl", value: "en-US"),
            URLQueryItem(name: "gl", value: "US"),
            URLQueryItem(name: "ceid", value: "US:en")
        ]
        guard let url = components?.url else { throw ServiceError.badURL }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.badResponse(-1) }
        guard (200..<300).contains(http.statusCode) else { throw ServiceError.badResponse(http.statusCode) }

        let parser = RSSParser()
        guard let items = parser.parse(data: data) else { throw ServiceError.parsing }
        return items.compactMap(Self.makeArticle)
    }

    // MARK: - Map a raw RSS item → Article

    private static func makeArticle(from item: RSSItem) -> Article? {
        guard let url = URL(string: item.link), !item.title.isEmpty else { return nil }
        return Article(
            id: item.link,
            title: cleanTitle(item.title, source: item.source),
            url: url,
            source: item.source.isEmpty ? "News" : item.source,
            publishedAt: parseDate(item.pubDate) ?? Date()
        )
    }

    /// Google News appends " - Source" to titles; strip it if present so the
    /// headline reads cleanly (the source is shown separately).
    private static func cleanTitle(_ title: String, source: String) -> String {
        guard !source.isEmpty, title.hasSuffix(" - \(source)") else { return title }
        return String(title.dropLast(source.count + 3))
    }

    /// RSS dates look like "Mon, 01 Jun 2026 21:40:00 GMT" (RFC 822).
    private static func parseDate(_ string: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        return f.date(from: string)
    }
}

// MARK: - RSS parsing (XMLParser delegate)

/// A bare RSS item as pulled from the XML, before mapping to `Article`.
struct RSSItem {
    var title = ""
    var link = ""
    var pubDate = ""
    var source = ""
}

/// Walks an RSS document with XMLParser and collects <item> entries.
/// XMLParser is event-driven: it calls didStartElement / foundCharacters /
/// didEndElement as it reads. We accumulate text per element and snapshot a
/// finished item each time we hit a closing </item>.
private final class RSSParser: NSObject, XMLParserDelegate {

    private var items: [RSSItem] = []
    private var current: RSSItem?
    private var currentElement = ""
    private var buffer = ""

    func parse(data: Data) -> [RSSItem]? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        return parser.parse() ? items : nil
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes attributeDict: [String: String] = [:]) {
        currentElement = elementName
        if elementName == "item" {
            current = RSSItem()
        }
        buffer = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        let text = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "title":   if current != nil { current?.title = text }
        case "link":    if current != nil { current?.link = text }
        case "pubDate": current?.pubDate = text
        case "source":  current?.source = text
        case "item":
            if let item = current { items.append(item) }
            current = nil
        default: break
        }
        buffer = ""
    }
}
