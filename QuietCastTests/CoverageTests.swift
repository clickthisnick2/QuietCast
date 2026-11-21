import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuietCastLogic

final class PlaybackTextTests: XCTestCase {
    func testHoursMinutesAndProgressSpan() {
        XCTAssertEqual(PlaybackText.hoursMinutes(-5), "0m")
        XCTAssertEqual(PlaybackText.hoursMinutes(60), "1m")
        XCTAssertEqual(PlaybackText.hoursMinutes(1e20), PlaybackText.hoursMinutes(Double(Int.max / 4)))
        XCTAssertEqual(PlaybackText.progressSpan(119), "1m")
        XCTAssertEqual(PlaybackText.progressSpan(59.999), "<1m")
    }

    func testTransportAndSpeechLabels() {
        XCTAssertEqual(PlaybackText.clock(0), "0:00")
        XCTAssertEqual(PlaybackText.clock(65), "1:05")
        XCTAssertEqual(PlaybackText.clock(3723), "1:02:03")
        XCTAssertEqual(PlaybackText.clock(-4), "0:00")
        XCTAssertEqual(PlaybackText.countdown(65), "1:05")
        XCTAssertEqual(PlaybackText.countdown(3723), "62:03")
        XCTAssertEqual(PlaybackText.rate(1), "1x")
        XCTAssertEqual(PlaybackText.rate(2), "2x")
        XCTAssertEqual(PlaybackText.rate(1.25), "1.2x")
        XCTAssertEqual(PlaybackText.rate(1.5), "1.5x")
        XCTAssertEqual(PlaybackText.rate(1.75), "1.8x")
        XCTAssertEqual(PlaybackText.spokenRemaining(0), "0 seconds")
        XCTAssertEqual(PlaybackText.spokenRemaining(1), "1 second")
        XCTAssertEqual(PlaybackText.spokenRemaining(61), "1 minute, 1 second")
        XCTAssertEqual(PlaybackText.spokenRemaining(120), "2 minutes")
        XCTAssertEqual(PlaybackText.spokenRemaining(3661), "1 hour, 1 minute, 1 second")
        XCTAssertEqual(PlaybackText.spokenRemaining(7200 + 120 + 2), "2 hours, 2 minutes, 2 seconds")
    }

    func testEpisodeDurationStrings() {
        XCTAssertEqual(PlaybackText.durationSeconds("3661"), 3661)
        XCTAssertEqual(PlaybackText.durationSeconds("45:30"), 2730)
        XCTAssertEqual(PlaybackText.durationSeconds("1:02:03"), 3723)
        XCTAssertEqual(PlaybackText.durationSeconds("  90 "), 90)
        XCTAssertEqual(PlaybackText.durationSeconds("00:01"), 1)
        XCTAssertNil(PlaybackText.durationSeconds(""))
        XCTAssertNil(PlaybackText.durationSeconds("0"))
        XCTAssertNil(PlaybackText.durationSeconds("0:00"))
        XCTAssertNil(PlaybackText.durationSeconds("nope"))
        XCTAssertNil(PlaybackText.durationSeconds("1:xx"))
        XCTAssertNil(PlaybackText.durationSeconds("1:2:3:4"))
    }
}

final class ModelIdentityTests: XCTestCase {
    func testPodcastAndEpisodeIdentity() {
        let show = Podcast(title: "Show", artworkURL: "", feedURL: "https://feeds.example.com/show")
        let renamed = Podcast(title: "Other", artworkURL: "x", feedURL: show.feedURL)
        XCTAssertEqual(show.id, show.feedURL)
        XCTAssertEqual(show, renamed)
        XCTAssertEqual(Set([show, renamed]).count, 1)

        let episode = sampleEpisode(guid: "ep-1")
        let same = sampleEpisode(guid: "ep-1", title: "Different")
        XCTAssertEqual(episode.id, "ep-1")
        XCTAssertEqual(episode, same)
        XCTAssertNotEqual(episode, sampleEpisode(guid: "ep-2"))
    }

    func testOlderThanBoundaryUsesTheDefaultClock() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: now)!
        let exact = sampleEpisode(guid: "exact", pubDateTimestamp: cutoff.timeIntervalSince1970)
        let older = sampleEpisode(guid: "older", pubDateTimestamp: cutoff.timeIntervalSince1970 - 1)
        XCTAssertEqual([exact, older].olderThan(days: 60, now: now).map(\.guid), ["older"])

        let undated = sampleEpisode(guid: "undated", pubDateTimestamp: nil)
        XCTAssertEqual([undated].olderThan(days: 1).map(\.guid), ["undated"])
    }
}

final class HTMLCleanerCoverageTests: XCTestCase {
    func testRemainingEntitiesWhitespaceAndURLs() {
        XCTAssertEqual(HTMLCleaner.clean("a&apos;b &#39; c"), "a'b ' c")
        XCTAssertEqual(HTMLCleaner.clean("&#8211; &#8212; &#8230;"), "\u{2013} \u{2014} \u{2026}")
        XCTAssertEqual(HTMLCleaner.clean("&#8216; &#8220; &#8221;"), "\u{2018} \u{201C} \u{201D}")
        XCTAssertEqual(HTMLCleaner.clean("&#65;"), "A")
        XCTAssertEqual(HTMLCleaner.clean("&#1114112;"), "&#1114112;")
        XCTAssertEqual(HTMLCleaner.clean("see   www.example.com/a   now"), "see now")
        XCTAssertEqual(HTMLCleaner.clean("<p class=\"x\">Hi</p>\n\nthere"), "Hi there")
        XCTAssertEqual(HTMLCleaner.clean(""), "")
    }
}

final class RSSParserCoverageTests: XCTestCase {
    func testArtworkGuidFallbackSummaryAndSkippedItem() {
        var data = Data(
            """
            <?xml version="1.0" encoding="ISO-8859-1"?>
            <rss><channel><title>Cafe
            """.utf8
        )
        data.append(
            contentsOf: Data("</title><itunes:image href=\"https://example.com/art.jpg\"/><item><title>Kept".utf8))
        data.append(0xE9)
        data.append(
            contentsOf: Data(
                """
                </title>
                <guid>   </guid>
                <enclosure url="https://example.com/a.mp3" type="audio/mpeg"/>
                <itunes:summary>Hello &amp; friends</itunes:summary>
                </item>
                <item><title>No audio</title><guid>skip</guid></item>
                </channel></rss>
                """.utf8
            ))

        let episodes = RSSParser(feedURL: "https://feeds.example.com/cafe").parse(data: data)
        XCTAssertEqual(episodes.count, 1)
        XCTAssertEqual(episodes[0].guid, "https://example.com/a.mp3")
        XCTAssertEqual(episodes[0].artworkURL, "https://example.com/art.jpg")
        XCTAssertEqual(episodes[0].descriptionText, "Hello & friends")
        XCTAssertEqual(episodes[0].podcastTitle, "Cafe")
        XCTAssertEqual(episodes[0].title, "Kept\u{00E9}")
    }

    func testValidXMLCharactersAreKeptAndControlsAreStripped() {
        let xml =
            "<rss><channel><title>T</title><item><title>A\u{0001}B\u{0009}C\u{E000}D\u{10000}</title><guid>g</guid><enclosure url=\"https://example.com/a.mp3\" type=\"audio/mpeg\"/></item></channel></rss>"
        let episodes = RSSParser(feedURL: "https://feeds.example.com/chars").parse(data: Data(xml.utf8))
        XCTAssertEqual(episodes.first?.title, "AB\u{0009}C\u{E000}D\u{10000}")
    }

    func testMissingEpisodesUseTheFeedHost() {
        let url = URL(string: "https://feeds.example.com/empty")!
        XCTAssertEqual(FeedService.podcastTitle(from: [], feedURL: url), "feeds.example.com")
    }

    func testBrokenTailKeepsEarlierEpisodes() {
        let xml = """
            <?xml version="1.0"?><rss><channel><title>Partial</title>
            <item><title>Kept</title><guid>keep</guid><enclosure url="https://example.com/a.mp3" type="audio/mpeg"/></item>
            <item><title>Broken
            """
        let parser = RSSParser(feedURL: "https://feeds.example.com/partial")
        let episodes = parser.parse(data: Data(xml.utf8))
        XCTAssertTrue(parser.parseFailed)
        XCTAssertEqual(episodes.map(\.guid), ["keep"])
    }
}

final class FeedServiceCoverageTests: XCTestCase {
    func testSchemeLessAndEmptyURLs() async {
        for raw in ["", "not a url", "relative/path"] {
            do {
                _ = try await FeedService.load(feedURL: raw)
                XCTFail("expected invalid URL for \(raw)")
            } catch FeedError.invalidURL {
            } catch {
                XCTFail("unexpected \(error) for \(raw)")
            }
        }
    }

    func testTransportFailures() async {
        let session = stubbedSession()
        await expectFeedError(
            "https://feeds.example.com/off", session: session, error: URLError(.notConnectedToInternet)
        ) { error in
            guard case FeedError.offline = error else { return false }
            return true
        }
        await expectFeedError(
            "https://feeds.example.com/lost", session: session, error: URLError(.networkConnectionLost)
        ) { error in
            guard case FeedError.offline = error else { return false }
            return true
        }
        await expectFeedError("https://feeds.example.com/slow", session: session, error: URLError(.timedOut)) { error in
            guard case FeedError.timedOut = error else { return false }
            return true
        }
        await expectFeedError("https://feeds.example.com/bad", session: session, error: URLError(.badServerResponse)) {
            error in
            guard case FeedError.other = error else { return false }
            return true
        }
    }

    func testNonHTTPResponseAndContentType() async throws {
        let session = stubbedSession()
        StubURLProtocol.reply = StubReply(status: nil, headers: [:], body: Data("hi".utf8), error: nil, http: false)
        do {
            _ = try await FeedService.load(feedURL: "https://feeds.example.com/raw", session: session)
            XCTFail("expected a non-HTTP response")
        } catch FeedError.notHTTP {
        } catch {
            XCTFail("unexpected \(error)")
        }

        let body = Data(
            "<rss><channel><title>T</title><item><title>E</title><guid>g</guid><enclosure url=\"https://example.com/a.mp3\" type=\"audio/mpeg\"/></item></channel></rss>"
                .utf8)
        StubURLProtocol.reply = StubReply(
            status: 200,
            headers: ["Content-Type": "application/rss+xml"],
            body: body,
            error: nil,
            http: true
        )
        let feed = try await FeedService.load(feedURL: "https://feeds.example.com/ok", session: session)
        XCTAssertEqual(feed.episodes.map(\.guid), ["g"])
        XCTAssertEqual(feed.contentType, "application/rss+xml")
        XCTAssertFalse(feed.parseFailed)
    }

    private func expectFeedError(
        _ url: String,
        session: URLSession,
        error: Error,
        matches: (Error) -> Bool
    ) async {
        StubURLProtocol.reply = StubReply(status: nil, headers: [:], body: Data(), error: error, http: true)
        do {
            _ = try await FeedService.load(feedURL: url, session: session)
            XCTFail("expected \(error)")
        } catch {
            XCTAssertTrue(matches(error), "unexpected \(error)")
        }
    }
}

final class iTunesSearchCoverageTests: XCTestCase {
    func testDecodesFeedsAndDropsResultsWithoutOne() async throws {
        let body = """
            {"results":[
              {"collectionId":1,"collectionName":"Show","artistName":"Ada","artworkUrl100":null,"feedUrl":"https://feeds.example.com/show","trackCount":3,"primaryGenreName":"Arts","contentAdvisoryRating":"Clean"},
              {"collectionId":2,"collectionName":"No Feed","artistName":"Bea"}
            ]}
            """
        StubURLProtocol.reply = StubReply(status: 200, headers: [:], body: Data(body.utf8), error: nil, http: true)
        let results = try await iTunesSearchService.search(term: "quiet cast", session: stubbedSession())
        XCTAssertEqual(results.map(\.collectionName), ["Show"])
        let podcast = results[0].toPodcast()
        XCTAssertEqual(podcast?.feedURL, "https://feeds.example.com/show")
        XCTAssertEqual(podcast?.artworkURL, "")
        XCTAssertEqual(results[0].id, 1)

        let missing = iTunesPodcast(
            collectionId: 9,
            collectionName: "Missing",
            artistName: "Bea",
            artworkUrl100: nil,
            feedUrl: nil,
            trackCount: nil,
            primaryGenreName: nil,
            contentAdvisoryRating: nil
        )
        XCTAssertNil(missing.toPodcast())
    }

    func testInvalidJSONThrows() async {
        StubURLProtocol.reply = StubReply(status: 200, headers: [:], body: Data("nope".utf8), error: nil, http: true)
        do {
            _ = try await iTunesSearchService.search(term: "x", session: stubbedSession())
            XCTFail("expected a decode error")
        } catch is DecodingError {
        } catch {
            XCTFail("unexpected \(error)")
        }
    }
}

final class AppSettingsCoverageTests: XCTestCase {
    func testEveryPreferenceRoundTrips() {
        let (settings, defaults, name) = temporarySettings()
        defer { defaults.removePersistentDomain(forName: name) }

        settings.autoPlayNext = false
        settings.maxVolume = 0.4
        settings.autoPauseMinutes = 15
        settings.playbackRate = 1.5
        settings.defaultSkipIntroSeconds = 30
        settings.noiseCancellationOn = true
        settings.systemVolumeCapNC = 0.3
        settings.systemVolumeFloorNC = 0.2
        settings.systemVolumeCapNoNC = 0.11
        settings.systemVolumeFloorNoNC = 0.05
        settings.systemVolumeCapEnabled = false
        settings.volumeRangeAlwaysOn = false
        settings.volumeRangeAutoReenableMinutes = 30
        settings.randomEpisodeAgeDays = 10
        settings.randomExcludedFeedURLs = ["https://feeds.example.com/a"]
        let turnLockBackOn = Date(timeIntervalSince1970: 1_700_000_000)
        settings.volumeRangeReenableAt = turnLockBackOn

        let reloaded = AppSettings(defaults: defaults)
        XCTAssertFalse(reloaded.autoPlayNext)
        XCTAssertEqual(reloaded.maxVolume, 0.4, accuracy: 0.0001)
        XCTAssertEqual(reloaded.autoPauseMinutes, 15)
        XCTAssertEqual(reloaded.playbackRate, 1.5, accuracy: 0.0001)
        XCTAssertEqual(reloaded.defaultSkipIntroSeconds, 30)
        XCTAssertTrue(reloaded.noiseCancellationOn)
        XCTAssertEqual(reloaded.systemVolumeCapNC, 0.3, accuracy: 0.0001)
        XCTAssertEqual(reloaded.systemVolumeFloorNC, 0.2, accuracy: 0.0001)
        XCTAssertEqual(reloaded.systemVolumeCapNoNC, 0.11, accuracy: 0.0001)
        XCTAssertEqual(reloaded.systemVolumeFloorNoNC, 0.05, accuracy: 0.0001)
        XCTAssertFalse(reloaded.systemVolumeCapEnabled)
        XCTAssertFalse(reloaded.volumeRangeAlwaysOn)
        XCTAssertEqual(reloaded.volumeRangeAutoReenableMinutes, 30)
        XCTAssertEqual(reloaded.randomEpisodeAgeDays, 10)
        XCTAssertEqual(reloaded.randomExcludedFeedURLs, ["https://feeds.example.com/a"])
        XCTAssertEqual(
            reloaded.volumeRangeReenableAt?.timeIntervalSince1970 ?? -1,
            turnLockBackOn.timeIntervalSince1970,
            accuracy: 1
        )
        XCTAssertEqual(reloaded.systemVolumeCap, 0.3, accuracy: 0.0001)
        XCTAssertEqual(reloaded.systemVolumeFloor, 0.2, accuracy: 0.0001)

        reloaded.volumeRangeReenableAt = nil
        XCTAssertNil(defaults.object(forKey: "volumeRangeReenableAt"))
        XCTAssertEqual(AppSettings.appName, "QuietCast")
        XCTAssertEqual(AppSettings.skipIntervalSeconds, 30)
        XCTAssertFalse(AppSettings.skipIntroOptions.isEmpty)
        XCTAssertEqual(AppSettings.shared.maxVolume, AppSettings.shared.maxVolume)
    }

    func testReactionsFollowTheActiveVolumeMode() {
        let (settings, defaults, name) = temporarySettings()
        defer { defaults.removePersistentDomain(forName: name) }
        let calls = ReactionLog()
        settings.reactions.clampOutputVolume = { calls.clamp += 1 }
        settings.reactions.applyPlaybackRate = { calls.rate += 1 }
        settings.reactions.enforceSystemVolumeCap = { calls.cap += 1 }
        settings.reactions.enforceSystemVolumeFloor = { calls.floor += 1 }
        settings.reactions.systemVolumeLockChanged = { calls.lock += 1 }
        settings.reactions.scheduleVolumeRangeReenable = { calls.schedule += 1 }

        settings.maxVolume = 0.5
        settings.playbackRate = 1.25
        settings.noiseCancellationOn = true
        settings.systemVolumeCapNC = 0.25
        settings.systemVolumeFloorNoNC = 0.08
        settings.systemVolumeCapEnabled = false
        settings.volumeRangeAutoReenableMinutes = 45
        settings.volumeRangeAlwaysOn = true
        settings.noiseCancellationOn = false

        XCTAssertEqual(calls.clamp, 1)
        XCTAssertEqual(calls.rate, 1)
        XCTAssertGreaterThanOrEqual(calls.cap, 1)
        XCTAssertGreaterThanOrEqual(calls.floor, 1)
        XCTAssertEqual(calls.lock, 1)
        XCTAssertEqual(calls.schedule, 1)
    }

    func testOffMainWriteStillNotifies() {
        let (settings, defaults, name) = temporarySettings()
        defer { defaults.removePersistentDomain(forName: name) }
        let exp = expectation(description: "clamp")
        settings.reactions.clampOutputVolume = { exp.fulfill() }
        DispatchQueue.global().async {
            settings.maxVolume = 0.33
        }
        wait(for: [exp], timeout: 2)
        XCTAssertEqual(settings.maxVolume, 0.33, accuracy: 0.0001)
    }
}

private final class ReactionLog: @unchecked Sendable {
    var clamp = 0
    var rate = 0
    var cap = 0
    var floor = 0
    var lock = 0
    var schedule = 0
}

final class PersistenceCoverageTests: XCTestCase {
    func testFreshLibraryPlaybackCacheAndClear() throws {
        let (persistence, directory) = try temporaryPersistence()
        defer { try? FileManager.default.removeItem(at: directory) }

        XCTAssertTrue(persistence.loadLibrary().podcasts.isEmpty)
        XCTAssertEqual(persistence.playbackPosition(for: "missing"), 0)
        XCTAssertFalse(persistence.isPlayed("missing"))
        XCTAssertNil(persistence.loadLastPlayedEpisode())
        XCTAssertNil(persistence.skipSeconds(for: "https://feeds.example.com/show"))
        XCTAssertNil(persistence.cachedEpisodes(for: "https://feeds.example.com/missing"))

        let episode = sampleEpisode(guid: "a/b:c")
        let feed = "https://feeds.example.com/show"
        persistence.cacheEpisodes([episode], for: feed)
        let audio = persistence.localFileURL(for: episode)
        XCTAssertEqual(audio.lastPathComponent, "download_a_b_c.mp3")
        try Data("audio".utf8).write(to: audio)
        XCTAssertTrue(persistence.isDownloaded(episode))
        persistence.excludeFromBackup(url: audio)
        persistence.excludeExistingDownloadsFromBackup()

        persistence.savePlaybackPosition(4, for: episode.guid)
        persistence.savePlaybackProgress(seconds: 12, guid: episode.guid, feedURL: feed)
        XCTAssertEqual(persistence.playbackPosition(for: episode.guid), 12, accuracy: 0.001)
        XCTAssertEqual(persistence.loadLastPlayedEpisode()?.guid, episode.guid)
        persistence.savePlaybackProgress(seconds: 13, guid: episode.guid, feedURL: nil)
        XCTAssertEqual(persistence.loadLibrary().lastPlayedEpisodeGUID, episode.guid)

        persistence.markPlayed(episode.guid)
        XCTAssertTrue(persistence.isPlayed(episode.guid))
        persistence.setSkipSeconds(15, for: feed)
        XCTAssertEqual(persistence.skipSeconds(for: feed), 15)
        persistence.setSkipSeconds(nil, for: feed)
        XCTAssertNil(persistence.skipSeconds(for: feed))
        persistence.setSkipSeconds(10, for: feed)

        let previous = AppSettings.shared.randomExcludedFeedURLs
        defer { AppSettings.shared.randomExcludedFeedURLs = previous }
        AppSettings.shared.randomExcludedFeedURLs = [feed, "https://feeds.example.com/keep"]

        persistence.removeAllData(for: Podcast(title: "Show", artworkURL: "", feedURL: feed))
        XCTAssertFalse(persistence.isDownloaded(episode))
        XCTAssertNil(persistence.cachedEpisodes(for: feed))
        XCTAssertEqual(persistence.playbackPosition(for: episode.guid), 0)
        XCTAssertFalse(persistence.isPlayed(episode.guid))
        XCTAssertNil(persistence.loadLastPlayedEpisode())
        XCTAssertNil(persistence.skipSeconds(for: feed))
        XCTAssertEqual(AppSettings.shared.randomExcludedFeedURLs, ["https://feeds.example.com/keep"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))

        try Data("x".utf8).write(to: directory.appendingPathComponent("download_left.mp3"))
        try Data("[]".utf8).write(to: directory.appendingPathComponent("cache_left.json"))
        persistence.update(flushImmediately: true) { library in
            library.podcasts = [Podcast(title: "Left", artworkURL: "", feedURL: "https://feeds.example.com/left")]
        }
        persistence.clearAllData()
        XCTAssertTrue(persistence.loadLibrary().podcasts.isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertFalse(names.contains { $0.hasPrefix("download_") || $0.hasPrefix("cache_") || $0 == "library.json" })
    }

    func testDebouncedSaveReachesDisk() async throws {
        let (persistence, directory) = try temporaryPersistence()
        defer { try? FileManager.default.removeItem(at: directory) }
        let libraryURL = directory.appendingPathComponent("library.json")
        persistence.update { library in
            library.podcasts = [Podcast(title: "Later", artworkURL: "", feedURL: "https://feeds.example.com/later")]
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: libraryURL.path))
        try await Task.sleep(nanoseconds: 1_200_000_000)
        let saved = try JSONDecoder().decode(LibraryData.self, from: Data(contentsOf: libraryURL))
        XCTAssertEqual(saved.podcasts.map(\.title), ["Later"])
    }

    func testUnbackupableLibraryIsNotReplaced() throws {
        let (persistence, directory) = try temporaryPersistence()
        defer { try? FileManager.default.removeItem(at: directory) }
        let libraryURL = directory.appendingPathComponent("library.json")
        try Data("{\"podcasts\":\"nope\"}".utf8).write(to: libraryURL)
        persistence.allowsCorruptBackup = false
        XCTAssertTrue(persistence.loadLibrary().podcasts.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: libraryURL.path))

        persistence.update(flushImmediately: true) { library in
            library.podcasts = [Podcast(title: "New", artworkURL: "", feedURL: "https://feeds.example.com/new")]
        }
        XCTAssertEqual(String(decoding: try Data(contentsOf: libraryURL), as: UTF8.self), "{\"podcasts\":\"nope\"}")
    }

    func testCorruptBackupUsesASecondNameInTheSameSecond() throws {
        let (_, directory) = try temporaryPersistence()
        defer { try? FileManager.default.removeItem(at: directory) }
        let libraryURL = directory.appendingPathComponent("library.json")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"

        var matched = false
        for _ in 0..<3 {
            let stamp = formatter.string(from: Date())
            try Data("reserved".utf8).write(to: directory.appendingPathComponent("library.json.corrupt-\(stamp)"))
            try Data("{\"podcasts\":\"nope\"}".utf8).write(to: libraryURL)
            let persistence = PersistenceManager()
            persistence.storageDirectoryOverride = directory
            _ = persistence.loadLibrary()
            if FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("library.json.corrupt-\(stamp)-1").path)
            {
                matched = true
                break
            }
        }
        XCTAssertTrue(matched)
    }

    func testDiskReloadNilCacheAndUnwritableDirectory() throws {
        let (persistence, directory) = try temporaryPersistence()
        defer { try? FileManager.default.removeItem(at: directory) }
        persistence.update(flushImmediately: true) { library in
            library.podcasts = [Podcast(title: "Disk", artworkURL: "", feedURL: "https://feeds.example.com/disk")]
        }
        let reloaded = PersistenceManager()
        reloaded.storageDirectoryOverride = directory
        XCTAssertEqual(reloaded.loadLibrary().podcasts.map(\.title), ["Disk"])

        let fresh = PersistenceManager()
        fresh.storageDirectoryOverride = directory
        fresh.flushToDisk()

        let blockedPath = directory.appendingPathComponent("not-a-directory")
        try Data("x".utf8).write(to: blockedPath)
        let blocked = PersistenceManager()
        blocked.storageDirectoryOverride = blockedPath
        blocked.excludeExistingDownloadsFromBackup()
        blocked.cacheEpisodes([sampleEpisode(guid: "nope")], for: "https://feeds.example.com/nope")
        blocked.removeAllData(for: Podcast(title: "None", artworkURL: "", feedURL: "https://feeds.example.com/none"))
        XCTAssertTrue(blocked.loadLibrary().podcasts.isEmpty)
    }

    func testDocumentsDirectoryWithoutOverride() {
        let url = PersistenceManager().documentsDirectory()
        XCTAssertFalse(url.path.isEmpty)
    }

    func testBadEpisodeCacheIsIgnored() throws {
        let (persistence, directory) = try temporaryPersistence()
        defer { try? FileManager.default.removeItem(at: directory) }
        let feed = "https://feeds.example.com/bad"
        persistence.cacheEpisodes([sampleEpisode(guid: "ok")], for: feed)
        XCTAssertEqual(persistence.cachedEpisodes(for: feed)?.map(\.guid), ["ok"])
        let cache = directory.appendingPathComponent("cache_https___feeds.example.com_bad.json")
        try Data("not-json".utf8).write(to: cache)
        XCTAssertNil(persistence.cachedEpisodes(for: feed))
    }
}

private struct StubReply {
    var status: Int?
    var headers: [String: String]
    var body: Data
    var error: Error?
    var http: Bool
}

private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var reply = StubReply(status: 200, headers: [:], body: Data(), error: nil, http: true)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let reply = Self.reply
        if let error = reply.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let url = request.url ?? URL(string: "https://example.com/")!
        let response: URLResponse
        if reply.http,
            let status = reply.status,
            let http = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: reply.headers)
        {
            response = http
        } else {
            response = URLResponse(
                url: url,
                mimeType: nil,
                expectedContentLength: reply.body.count,
                textEncodingName: nil
            )
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !reply.body.isEmpty {
            client?.urlProtocol(self, didLoad: reply.body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func stubbedSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: configuration)
}

private func temporarySettings() -> (AppSettings, UserDefaults, String) {
    let name = "quietcast-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return (AppSettings(defaults: defaults), defaults, name)
}

private func temporaryPersistence() throws -> (PersistenceManager, URL) {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("quietcast-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let persistence = PersistenceManager()
    persistence.storageDirectoryOverride = directory
    return (persistence, directory)
}

private func sampleEpisode(guid: String, title: String? = nil, pubDateTimestamp: Double? = nil) -> Episode {
    Episode(
        guid: guid,
        title: title ?? guid,
        descriptionText: "",
        pubDate: "",
        pubDateTimestamp: pubDateTimestamp,
        duration: "",
        audioURL: "https://example.com/\(guid).mp3",
        podcastTitle: "Show",
        artworkURL: ""
    )
}
