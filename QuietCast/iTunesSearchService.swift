import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct iTunesSearchResult: Decodable {
    let results: [iTunesPodcast]
}

struct iTunesPodcast: Decodable, Identifiable {
    let collectionId: Int
    let collectionName: String
    let artistName: String
    let artworkUrl100: String?
    let feedUrl: String?
    let trackCount: Int?
    let primaryGenreName: String?
    let contentAdvisoryRating: String?

    var id: Int { collectionId }

    func toPodcast() -> Podcast? {
        guard let feedUrl else { return nil }
        return Podcast(
            title: collectionName,
            artworkURL: artworkUrl100 ?? "",
            feedURL: feedUrl
        )
    }
}

enum iTunesSearchService {
    static func search(term: String, session: URLSession = .shared) async throws -> [iTunesPodcast] {
        guard let encoded = term.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(string: "https://itunes.apple.com/search?media=podcast&term=\(encoded)")
        else {
            return []
        }
        let (data, _) = try await session.data(from: url)
        let result = try JSONDecoder().decode(iTunesSearchResult.self, from: data)
        return result.results.filter { $0.feedUrl != nil }
    }
}
