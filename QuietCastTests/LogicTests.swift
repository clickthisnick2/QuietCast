import XCTest
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
@testable import QuietCastLogic

final class HTMLCleanerTests: XCTestCase {
    func testAmpIsDecodedAfterOtherNamedEntities() {
        XCTAssertEqual(HTMLCleaner.clean("&amp;lt;"), "&lt;")
        XCTAssertEqual(HTMLCleaner.clean("&lt;"), "<")
        XCTAssertEqual(HTMLCleaner.clean("&amp;"), "&")
        XCTAssertEqual(HTMLCleaner.clean("&gt;"), ">")
        XCTAssertEqual(HTMLCleaner.clean("&quot;"), "\"")
    }

    func testNbspAndNumericSpaceBecomeSpaces() {
        XCTAssertEqual(HTMLCleaner.clean("a&nbsp;b"), "a b")
        XCTAssertEqual(HTMLCleaner.clean("a&#160;b"), "a b")
        XCTAssertEqual(HTMLCleaner.clean("&#8217;"), "\u{2019}")
    }

    func testTagsAndURLsAreStripped() {
        XCTAssertEqual(HTMLCleaner.clean("<p>Hello</p>"), "Hello")
        XCTAssertEqual(HTMLCleaner.clean("See https://example.com/a now"), "See now")
    }
}

final class DurationFormatTests: XCTestCase {
    func testHoursAndMinutes() {
        XCTAssertEqual(PlaybackText.hoursMinutes(3723), "1h 2m")
        XCTAssertEqual(PlaybackText.hoursMinutes(3600), "1h 0m")
        XCTAssertEqual(PlaybackText.hoursMinutes(90), "1m")
        XCTAssertEqual(PlaybackText.hoursMinutes(59), "0m")
        XCTAssertEqual(PlaybackText.hoursMinutes(0), "0m")
        XCTAssertEqual(PlaybackText.hoursMinutes(.nan), "0m")
    }

    func testProgressSpanUsesLessThanOneMinute() {
        XCTAssertEqual(PlaybackText.progressSpan(0), "<1m")
        XCTAssertEqual(PlaybackText.progressSpan(59.9), "<1m")
        XCTAssertEqual(PlaybackText.progressSpan(60), "1m")
        XCTAssertEqual(PlaybackText.progressSpan(3723), "1h 2m")
        XCTAssertEqual(PlaybackText.progressSpan(.nan), "<1m")
        XCTAssertEqual(PlaybackText.progressSpan(-5), "<1m")
    }
}

final class TimeGateTests: XCTestCase {
    func testSearchWindowAndNightHours() {
        XCTAssertTrue(TimeGate.searchAllowed(at: date(hour: 8)))
        XCTAssertTrue(TimeGate.searchAllowed(at: date(hour: 19, minute: 59)))
        XCTAssertFalse(TimeGate.searchAllowed(at: date(hour: 7, minute: 59)))
        XCTAssertFalse(TimeGate.searchAllowed(at: date(hour: 20)))
        XCTAssertFalse(TimeGate.searchAllowed(at: date(hour: 0)))

        let night = date(hour: 21)
        XCTAssertTrue(TimeGate.isNighttime(at: night))
        XCTAssertFalse(TimeGate.isNighttime(at: date(hour: 12)))
        XCTAssertEqual(TimeGate.searchHoursText, "8 AM – 8 PM")
        XCTAssertEqual(TimeGate.nightHoursText, "8 PM – 8 AM")
        XCTAssertEqual(TimeGate.searchHoursSentence, "8 AM and 8 PM")
    }

    private func date(hour: Int, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 15
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components)!
    }
}

final class EpisodeAgeFilterTests: XCTestCase {
    func testOlderThanIncludesUndatedAndExcludesYoungEpisodes() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let old = makeEpisode(
            guid: "old",
            pubDateTimestamp: now.addingTimeInterval(-90 * 24 * 60 * 60).timeIntervalSince1970
        )
        let young = makeEpisode(
            guid: "young",
            pubDateTimestamp: now.addingTimeInterval(-2 * 24 * 60 * 60).timeIntervalSince1970
        )
        let undated = makeEpisode(guid: "undated", pubDateTimestamp: nil)

        let picked = [old, young, undated].olderThan(days: 60, now: now).map(\.guid)
        XCTAssertEqual(picked, ["old", "undated"])
    }
}

final class RSSParserTests: XCTestCase {
    func testDurationsAndDates() {
        let parser = RSSParser(feedURL: "https://feeds.example.com/show")
        let episodes = parser.parse(data: Data(sampleFeed.utf8))
        XCTAssertFalse(parser.parseFailed)
        XCTAssertEqual(episodes.map(\.duration), ["3661", "45:30", "1:02:03"])
        XCTAssertEqual(episodes.map(\.guid), ["sec-1", "mmss-1", "hh-1"])
        XCTAssertEqual(episodes.map(\.podcastTitle), ["Sample Show", "Sample Show", "Sample Show"])

        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2002
        components.month = 10
        components.day = 2
        components.hour = 13
        let expected = components.date!.timeIntervalSince1970
        XCTAssertEqual(episodes[0].pubDateTimestamp ?? -1, expected, accuracy: 1)
        XCTAssertFalse(episodes[0].pubDate.isEmpty)
        XCTAssertNotEqual(episodes[0].pubDate, "Wed, 02 Oct 2002 13:00:00 +0000")

        XCTAssertNil(episodes[1].pubDateTimestamp)
        XCTAssertEqual(episodes[1].pubDate, "not-a-date")
        XCTAssertNil(episodes[2].pubDateTimestamp)
    }

    func testEmptyFeed() {
        let parser = RSSParser(feedURL: "https://feeds.example.com/empty")
        let episodes = parser.parse(data: Data(emptyFeed.utf8))
        XCTAssertFalse(parser.parseFailed)
        XCTAssertTrue(episodes.isEmpty)
    }

    func testInvalidFeed() {
        let parser = RSSParser(feedURL: "https://feeds.example.com/bad")
        let episodes = parser.parse(data: Data("this is not xml <<<".utf8))
        XCTAssertTrue(parser.parseFailed)
        XCTAssertTrue(episodes.isEmpty)
    }

    func testBlankTitleFallsBackToHostThenUnknown() {
        let parser = RSSParser(feedURL: "https://feeds.example.com/blank")
        let episodes = parser.parse(data: Data(blankTitleFeed.utf8))
        XCTAssertEqual(episodes.first?.podcastTitle, "")
        let hostURL = URL(string: "https://feeds.example.com/blank")!
        XCTAssertEqual(FeedService.podcastTitle(from: episodes, feedURL: hostURL), "feeds.example.com")

        let titled = RSSParser(feedURL: "https://feeds.example.com/show").parse(data: Data(sampleFeed.utf8))
        XCTAssertEqual(FeedService.podcastTitle(from: titled, feedURL: hostURL), "Sample Show")

        let noHost = URL(string: "feed:show")!
        XCTAssertEqual(FeedService.podcastTitle(from: episodes, feedURL: noHost), "Unknown Podcast")
    }
}

final class FeedServiceTests: XCTestCase {
    func testInvalidURL() async {
        do {
            _ = try await FeedService.load(feedURL: "not a url")
            XCTFail("expected an invalid URL")
        } catch FeedError.invalidURL {
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testLoadsFixtureOverHTTP() async throws {
        let server = try FixtureHTTPServer(body: Data(sampleFeed.utf8))
        defer { server.stop() }
        let feed = try await FeedService.load(feedURL: server.url)
        XCTAssertEqual(feed.episodes.count, 3)
        XCTAssertFalse(feed.parseFailed)
        XCTAssertEqual(feed.episodes.map(\.duration), ["3661", "45:30", "1:02:03"])
    }

    func testHTTPError() async throws {
        let server = try FixtureHTTPServer(body: Data("nope".utf8), status: 500)
        defer { server.stop() }
        do {
            _ = try await FeedService.load(feedURL: server.url)
            XCTFail("expected an HTTP error")
        } catch FeedError.httpStatus(500) {
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}

final class LibraryDataTests: XCTestCase {
    func testExtraAuthorKeyAndMissingKeysStillDecode() throws {
        let old = """
            {"podcasts":[{"title":"Show","author":"Ada","artworkURL":"https://example.com/a.png","feedURL":"https://feeds.example.com/show"}],"downloadedEpisodeGUIDs":["ep-1"]}
            """
        let library = try JSONDecoder().decode(LibraryData.self, from: Data(old.utf8))
        XCTAssertEqual(library.podcasts.map(\.title), ["Show"])
        XCTAssertEqual(library.podcasts.map(\.feedURL), ["https://feeds.example.com/show"])
        XCTAssertEqual(library.downloadedEpisodeGUIDs, ["ep-1"])
        XCTAssertTrue(library.playbackPositions.isEmpty)
        XCTAssertTrue(library.playedEpisodeGUIDs.isEmpty)
        XCTAssertNil(library.lastPlayedEpisodeGUID)
        XCTAssertNil(library.lastPlayedFeedURL)
        XCTAssertTrue(library.crownPodcastRotation.isEmpty)
        XCTAssertTrue(library.podcastSkipSeconds.isEmpty)

        let sparse = try JSONDecoder().decode(LibraryData.self, from: Data("{}".utf8))
        XCTAssertTrue(sparse.podcasts.isEmpty)
        XCTAssertTrue(sparse.downloadedEpisodeGUIDs.isEmpty)
    }

    func testCorruptFileIsMovedAsideAndALaterSaveCanReplaceIt() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quietcast-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let libraryURL = directory.appendingPathComponent("library.json")
        try Data("{\"podcasts\":\"nope\"}".utf8).write(to: libraryURL)

        let persistence = PersistenceManager()
        persistence.storageDirectoryOverride = directory
        let loaded = persistence.loadLibrary()
        XCTAssertTrue(loaded.podcasts.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: libraryURL.path))

        let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("library.json.corrupt-") }
        XCTAssertEqual(backups.count, 1)

        persistence.update(flushImmediately: true) { library in
            library.podcasts = [
                Podcast(title: "Recovered", artworkURL: "", feedURL: "https://feeds.example.com/recovered")
            ]
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: libraryURL.path))
        let restored = try JSONDecoder().decode(LibraryData.self, from: Data(contentsOf: libraryURL))
        XCTAssertEqual(restored.podcasts.map(\.title), ["Recovered"])
        let backupsAfterSave = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )
        .filter { $0.lastPathComponent.hasPrefix("library.json.corrupt-") }
        XCTAssertEqual(backupsAfterSave.count, 1)
    }
}

final class AppSettingsDefaultTests: XCTestCase {
    func testMissingKeysUseAppSettingsDefaultsAndWritesRoundTrip() {
        let name = "quietcast-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        defer { defaults.removePersistentDomain(forName: name) }

        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.autoPlayNext)
        XCTAssertEqual(settings.maxVolume, 1.0, accuracy: 0.0001)
        XCTAssertEqual(settings.autoPauseMinutes, 120)
        XCTAssertFalse(settings.noiseCancellationOn)
        XCTAssertEqual(settings.systemVolumeCapNC, 0.20, accuracy: 0.0001)
        XCTAssertEqual(settings.systemVolumeFloorNC, 0.10, accuracy: 0.0001)
        XCTAssertEqual(settings.systemVolumeCapNoNC, 0.14, accuracy: 0.0001)
        XCTAssertEqual(settings.systemVolumeFloorNoNC, 0.09, accuracy: 0.0001)
        XCTAssertEqual(settings.systemVolumeCap, 0.14, accuracy: 0.0001)
        XCTAssertEqual(settings.systemVolumeFloor, 0.09, accuracy: 0.0001)
        XCTAssertTrue(settings.systemVolumeCapEnabled)
        XCTAssertTrue(settings.volumeRangeAlwaysOn)
        XCTAssertEqual(settings.volumeRangeAutoReenableMinutes, 120)
        XCTAssertNil(settings.volumeRangeReenableAt)
        XCTAssertEqual(settings.randomEpisodeAgeDays, 60)
        XCTAssertEqual(settings.randomExcludedFeedURLs, [])
        XCTAssertEqual(settings.playbackRate, 1.0, accuracy: 0.0001)
        XCTAssertEqual(settings.defaultSkipIntroSeconds, 0)

        settings.maxVolume = 0.5
        settings.noiseCancellationOn = true
        let reloaded = AppSettings(defaults: defaults)
        XCTAssertEqual(reloaded.maxVolume, 0.5, accuracy: 0.0001)
        XCTAssertTrue(reloaded.noiseCancellationOn)
        XCTAssertEqual(reloaded.systemVolumeCap, 0.20, accuracy: 0.0001)
    }
}

private let sampleFeed = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
    <channel>
    <title>Sample Show</title>
    <item>
    <title>Seconds</title>
    <guid>sec-1</guid>
    <pubDate>Wed, 02 Oct 2002 13:00:00 +0000</pubDate>
    <itunes:duration>3661</itunes:duration>
    <enclosure url="https://example.com/a.mp3" type="audio/mpeg"/>
    </item>
    <item>
    <title>Minutes</title>
    <guid>mmss-1</guid>
    <pubDate>not-a-date</pubDate>
    <itunes:duration>45:30</itunes:duration>
    <enclosure url="https://example.com/b.mp3" type="audio/mpeg"/>
    </item>
    <item>
    <title>Hours</title>
    <guid>hh-1</guid>
    <itunes:duration>1:02:03</itunes:duration>
    <enclosure url="https://example.com/c.mp3" type="audio/mpeg"/>
    </item>
    </channel>
    </rss>
    """

private let emptyFeed = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd"><channel><title>Empty</title></channel></rss>
    """

private let blankTitleFeed = """
    <?xml version="1.0" encoding="UTF-8"?>
    <rss version="2.0" xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd">
    <channel>
    <title>   </title>
    <item>
    <title>Episode</title>
    <guid>blank-1</guid>
    <enclosure url="https://example.com/e.mp3" type="audio/mpeg"/>
    </item>
    </channel>
    </rss>
    """

private func makeEpisode(guid: String, pubDateTimestamp: Double?) -> Episode {
    Episode(
        guid: guid,
        title: guid,
        descriptionText: "",
        pubDate: "",
        pubDateTimestamp: pubDateTimestamp,
        duration: "",
        audioURL: "https://example.com/\(guid).mp3",
        podcastTitle: "Show",
        artworkURL: ""
    )
}

/// Tiny HTTP server so FeedService can be tested without the network.
private final class FixtureHTTPServer {
    let url: String
    private let server: Server

    init(body: Data, status: Int = 200) throws {
        let socket = Server()
        socket.start(body: body, status: status)
        server = socket
        url = "http://127.0.0.1:\(socket.port)/feed.xml"
    }

    func stop() {
        server.stop()
    }
}

private final class Server {
    private var fd: Int32 = -1
    private var client: Int32 = -1
    private(set) var port: UInt16 = 0
    private var running = true

    func start(body: Data, status: Int) {
        fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        var option: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &option, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0
        withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { raw in
                _ = bind(fd, raw, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        _ = listen(fd, 1)
        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &bound) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { raw in
                _ = getsockname(fd, raw, &length)
            }
        }
        port = UInt16(bigEndian: bound.sin_port)

        let header = """
            HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")\r
            Content-Type: application/rss+xml\r
            Content-Length: \(body.count)\r
            Connection: close\r
            \r

            """
        let payload = Data(header.utf8) + body
        let listenFD = fd
        Thread.detachNewThread {
            var clientAddress = sockaddr_in()
            var clientLength = socklen_t(MemoryLayout<sockaddr_in>.size)
            let accepted = withUnsafeMutablePointer(to: &clientAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { raw in
                    accept(listenFD, raw, &clientLength)
                }
            }
            self.client = accepted
            guard accepted >= 0 else { return }
            var buffer = [UInt8](repeating: 0, count: 2048)
            _ = read(accepted, &buffer, buffer.count)
            payload.withUnsafeBytes { raw in
                _ = write(accepted, raw.baseAddress, raw.count)
            }
            close(accepted)
        }
        Thread.sleep(forTimeInterval: 0.05)
    }

    func stop() {
        running = false
        if client >= 0 { close(client) }
        if fd >= 0 { close(fd) }
    }
}
