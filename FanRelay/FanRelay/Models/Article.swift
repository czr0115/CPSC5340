import Foundation

/// One news article from a Google News RSS feed.
///
/// Mapped from an RSS <item>. Google News doesn't give reliable per-article
/// thumbnails, so we skip images and show source + time — the spec's headline,
/// source, and time, which is the honest set of fields this feed provides.
struct Article: Identifiable, Equatable {
    let id: String          // the article link, unique per item
    let title: String       // cleaned headline (source suffix stripped)
    let url: URL            // tap target → in-app reader
    let source: String      // e.g. "ESPN"
    let publishedAt: Date

    /// "2h", "5h", "3d" style age for compact display.
    var age: String {
        let seconds = Date().timeIntervalSince(publishedAt)
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(max(minutes, 1))m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)d"
    }
}
