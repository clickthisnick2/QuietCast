import Foundation

struct Podcast: Codable, Identifiable, Equatable, Hashable {
    var id: String { feedURL }
    let title: String
    let artworkURL: String
    let feedURL: String

    static func == (lhs: Podcast, rhs: Podcast) -> Bool {
        lhs.feedURL == rhs.feedURL
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(feedURL)
    }
}

struct Episode: Codable, Identifiable, Equatable {
    var id: String { guid }
    let guid: String
    let title: String
    let descriptionText: String
    let pubDate: String
    /// Parsed publication date as seconds since 1970, or nil when the feed date is not valid.
    let pubDateTimestamp: Double?
    let duration: String
    let audioURL: String
    let podcastTitle: String
    let artworkURL: String

    static func == (lhs: Episode, rhs: Episode) -> Bool {
        lhs.guid == rhs.guid
    }
}

extension Array where Element == Episode {
    /// Episodes older than `days`. Episodes with no publication date are included.
    func olderThan(days: Int, now: Date = Date()) -> [Episode] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: now) ?? now
        let cutoffTimestamp = cutoff.timeIntervalSince1970
        return filter { episode in
            guard let timestamp = episode.pubDateTimestamp else { return true }
            return timestamp < cutoffTimestamp
        }
    }
}
