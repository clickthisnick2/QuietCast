import Foundation
#if canImport(os)
import os
#endif

#if !canImport(os)
/// Stand-in for `os.Logger` when the logic library is built on Linux.
struct Logger {
    init(subsystem: String, category: String) {}
    func info(_ message: String) {}
    func error(_ message: String) {}
    func warning(_ message: String) {}
}
#endif

struct LibraryData: Codable {
    var podcasts: [Podcast]
    var downloadedEpisodeGUIDs: Set<String>
    var playbackPositions: [String: Double]
    var playedEpisodeGUIDs: Set<String>
    var lastPlayedEpisodeGUID: String?
    var lastPlayedFeedURL: String?
    var crownPodcastRotation: [String]
    var podcastSkipSeconds: [String: Int]  // feedURL -> custom skip duration in seconds

    init(
        podcasts: [Podcast] = [],
        downloadedEpisodeGUIDs: Set<String> = [],
        playbackPositions: [String: Double] = [:],
        playedEpisodeGUIDs: Set<String> = [],
        lastPlayedEpisodeGUID: String? = nil,
        lastPlayedFeedURL: String? = nil,
        crownPodcastRotation: [String] = [],
        podcastSkipSeconds: [String: Int] = [:]
    ) {
        self.podcasts = podcasts
        self.downloadedEpisodeGUIDs = downloadedEpisodeGUIDs
        self.playbackPositions = playbackPositions
        self.playedEpisodeGUIDs = playedEpisodeGUIDs
        self.lastPlayedEpisodeGUID = lastPlayedEpisodeGUID
        self.lastPlayedFeedURL = lastPlayedFeedURL
        self.crownPodcastRotation = crownPodcastRotation
        self.podcastSkipSeconds = podcastSkipSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Missing keys are treated as empty so an older library.json still loads.
        // A present key with the wrong type still throws and is backed up.
        podcasts = try container.decodeIfPresent([Podcast].self, forKey: .podcasts) ?? []
        downloadedEpisodeGUIDs = try container.decodeIfPresent(Set<String>.self, forKey: .downloadedEpisodeGUIDs) ?? []
        playbackPositions = try container.decodeIfPresent([String: Double].self, forKey: .playbackPositions) ?? [:]
        playedEpisodeGUIDs = try container.decodeIfPresent(Set<String>.self, forKey: .playedEpisodeGUIDs) ?? []
        lastPlayedEpisodeGUID = try container.decodeIfPresent(String.self, forKey: .lastPlayedEpisodeGUID)
        lastPlayedFeedURL = try container.decodeIfPresent(String.self, forKey: .lastPlayedFeedURL)
        crownPodcastRotation = try container.decodeIfPresent([String].self, forKey: .crownPodcastRotation) ?? []
        podcastSkipSeconds = try container.decodeIfPresent([String: Int].self, forKey: .podcastSkipSeconds) ?? [:]
    }
}

final class PersistenceManager {
    static let shared = PersistenceManager()
    static let appGroupID = "group.com.quietcast.shared"

    private let fileManager = FileManager.default
    private let logger = Logger(subsystem: "com.quietcast", category: "PersistenceManager")

    /// Tests point this at a temporary folder. Nil uses the app group container or Documents.
    var storageDirectoryOverride: URL?

    /// Tests set this to false to keep an unreadable library.json in place.
    var allowsCorruptBackup = true

    init() {}

    /// In-memory cache — avoids repeated disk reads
    private var cachedLibrary: LibraryData?
    private var saveTask: Task<Void, Never>?
    /// True when library.json could not be decoded and could not be moved aside.
    /// Writes stay off so a later save cannot replace the unread file with an empty one.
    private var blockOverwrite = false

    private var libraryFileURL: URL {
        documentsDirectory().appendingPathComponent("library.json")
    }

    func loadLibrary() -> LibraryData {
        if let cached = cachedLibrary {
            return cached
        }
        let url = libraryFileURL
        guard let data = try? Data(contentsOf: url) else {
            logger.info("No library file found at \(url.path) — starting fresh.")
            let empty = LibraryData(podcasts: [], downloadedEpisodeGUIDs: [])
            cachedLibrary = empty
            return empty
        }
        do {
            let library = try JSONDecoder().decode(LibraryData.self, from: data)
            logger.info("Loaded library with \(library.podcasts.count) podcasts from \(url.path)")
            cachedLibrary = library
            return library
        } catch {
            logger.error("Failed to decode library.json: \(error.localizedDescription)")
            if backupCorruptLibrary(at: url) {
                blockOverwrite = false
            } else {
                blockOverwrite = true
                logger.error("library.json was left in place. Saves are blocked so it is not overwritten.")
            }
            let empty = LibraryData(podcasts: [], downloadedEpisodeGUIDs: [])
            cachedLibrary = empty
            return empty
        }
    }

    /// Move an unreadable library.json to `library.json.corrupt-<date>` so a later save cannot destroy it.
    private func backupCorruptLibrary(at url: URL) -> Bool {
        guard allowsCorruptBackup else { return false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let directory = url.deletingLastPathComponent()
        var destination = directory.appendingPathComponent("library.json.corrupt-\(stamp)")
        var attempt = 1
        while fileManager.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("library.json.corrupt-\(stamp)-\(attempt)")
            attempt += 1
        }
        do {
            try fileManager.moveItem(at: url, to: destination)
            logger.error("Moved unreadable library.json to \(destination.lastPathComponent)")
            return true
        } catch {
            logger.error("Could not back up library.json: \(error.localizedDescription)")
            return false
        }
    }

    private func saveLibrary(_ library: LibraryData) {
        cachedLibrary = library
        scheduleSave()
    }

    /// Load the in-memory library, change it, and save.
    /// Position updates pass `flushImmediately` so one write hits disk now.
    /// Other edits stay on the short debounced save.
    func update(flushImmediately: Bool = false, _ mutate: (inout LibraryData) -> Void) {
        var library = loadLibrary()
        mutate(&library)
        if flushImmediately {
            cachedLibrary = library
            flushToDisk()
        } else {
            saveLibrary(library)
        }
    }

    /// Debounced disk write — coalesces rapid saves (e.g. position updates) into one write
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 second debounce
            guard !Task.isCancelled else { return }
            self.writeToDisk()
        }
    }

    /// Immediately write to disk (used by clearAllData and for critical saves)
    func flushToDisk() {
        saveTask?.cancel()
        writeToDisk()
    }

    private func writeToDisk() {
        guard !blockOverwrite else {
            logger.error("Refusing to overwrite library.json after a decode failure that could not be backed up.")
            return
        }
        guard let library = cachedLibrary else { return }
        do {
            let data = try JSONEncoder().encode(library)
            try data.write(to: libraryFileURL, options: .atomic)
        } catch {
            logger.error("Failed to write library to disk: \(error.localizedDescription)")
        }
    }

    func documentsDirectory() -> URL {
        if let storageDirectoryOverride {
            return storageDirectoryOverride
        }
        #if os(iOS) || os(macOS) || os(tvOS) || os(watchOS) || os(visionOS)
        if let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) {
            return groupURL
        }
        logger.warning(
            "App Group container not available for '\(Self.appGroupID)' — falling back to Documents directory. Data will not persist across reinstalls."
        )
        #endif
        return fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func localFileURL(for episode: Episode) -> URL {
        localFileURL(forEpisodeGUID: episode.guid)
    }

    /// Destination path for a download. Uses only the GUID so a finished
    /// background task can be saved after relaunch, when the Episode is gone.
    func localFileURL(forEpisodeGUID guid: String) -> URL {
        storageFile(prefix: "download_", raw: guid, ext: "mp3")
    }

    func isDownloaded(_ episode: Episode) -> Bool {
        fileManager.fileExists(atPath: localFileURL(for: episode).path)
    }

    /// Keep downloaded audio out of iCloud backup. The files are large and can be fetched again.
    func excludeFromBackup(url: URL) {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutable = url
        do {
            try mutable.setResourceValues(values)
        } catch {
            logger.error("Failed to exclude \(url.lastPathComponent) from backup: \(error.localizedDescription)")
        }
    }

    func excludeExistingDownloadsFromBackup() {
        let docs = documentsDirectory()
        guard let files = try? fileManager.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil) else {
            return
        }
        for file in files where file.lastPathComponent.hasPrefix("download_") {
            excludeFromBackup(url: file)
        }
    }

    func savePlaybackPosition(_ seconds: Double, for guid: String) {
        update(flushImmediately: true) { library in
            library.playbackPositions[guid] = seconds
        }
    }

    /// Position and last-played episode in one disk write. Used by the playback tick.
    func savePlaybackProgress(seconds: Double, guid: String, feedURL: String?) {
        update(flushImmediately: true) { library in
            library.playbackPositions[guid] = seconds
            if let feedURL {
                library.lastPlayedEpisodeGUID = guid
                library.lastPlayedFeedURL = feedURL
            }
        }
    }

    func playbackPosition(for guid: String) -> Double {
        loadLibrary().playbackPositions[guid] ?? 0
    }

    func markPlayed(_ guid: String) {
        update { library in
            library.playedEpisodeGUIDs.insert(guid)
        }
    }

    func isPlayed(_ guid: String) -> Bool {
        loadLibrary().playedEpisodeGUIDs.contains(guid)
    }

    // MARK: - Last Played Episode

    /// Loads the last played episode from the episode cache, if available.
    func loadLastPlayedEpisode() -> Episode? {
        let library = loadLibrary()
        guard let guid = library.lastPlayedEpisodeGUID,
            let feedURL = library.lastPlayedFeedURL,
            let episodes = cachedEpisodes(for: feedURL)
        else {
            return nil
        }
        return episodes.first { $0.guid == guid }
    }

    // MARK: - Per-Podcast Skip Duration

    func skipSeconds(for feedURL: String) -> Int? {
        loadLibrary().podcastSkipSeconds[feedURL]
    }

    func setSkipSeconds(_ seconds: Int?, for feedURL: String) {
        update { library in
            library.podcastSkipSeconds[feedURL] = seconds
        }
    }

    // MARK: - Episode Cache

    private func episodeCacheURL(for feedURL: String) -> URL {
        storageFile(prefix: "cache_", raw: feedURL, ext: "json")
    }

    private func storageFile(prefix: String, raw: String, ext: String) -> URL {
        let safe =
            raw
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return documentsDirectory().appendingPathComponent("\(prefix)\(safe).\(ext)")
    }

    func cachedEpisodes(for feedURL: String) -> [Episode]? {
        let url = episodeCacheURL(for: feedURL)
        guard let data = try? Data(contentsOf: url),
            let episodes = try? JSONDecoder().decode([Episode].self, from: data)
        else {
            return nil
        }
        return episodes
    }

    func cacheEpisodes(_ episodes: [Episode], for feedURL: String) {
        let url = episodeCacheURL(for: feedURL)
        do {
            let data = try JSONEncoder().encode(episodes)
            try data.write(to: url, options: .atomic)
        } catch {
            logger.error("Failed to cache episodes for \(feedURL): \(error.localizedDescription)")
        }
    }

    /// Remove all local data associated with a podcast: cached episodes, downloaded audio, and playback state.
    func removeAllData(for podcast: Podcast) {
        let feedURL = podcast.feedURL

        // Find episode GUIDs from the local cache so we can clean up without a network call
        let cachedEpisodes = cachedEpisodes(for: feedURL) ?? []
        let guids = Set(cachedEpisodes.map { $0.guid })

        for episode in cachedEpisodes {
            let fileURL = localFileURL(for: episode)
            try? fileManager.removeItem(at: fileURL)
        }
        try? fileManager.removeItem(at: episodeCacheURL(for: feedURL))

        update { library in
            library.downloadedEpisodeGUIDs.subtract(guids)
            for guid in guids {
                library.playbackPositions.removeValue(forKey: guid)
                library.playedEpisodeGUIDs.remove(guid)
            }
            if library.lastPlayedFeedURL == feedURL
                || guids.contains(library.lastPlayedEpisodeGUID ?? "")
            {
                library.lastPlayedEpisodeGUID = nil
                library.lastPlayedFeedURL = nil
            }
            library.podcastSkipSeconds.removeValue(forKey: feedURL)
        }

        let excluded = AppSettings.shared.randomExcludedFeedURLs
        let kept = excluded.filter { $0 != feedURL }
        if kept.count != excluded.count {
            AppSettings.shared.randomExcludedFeedURLs = kept
        }
    }

    func clearAllData() {
        blockOverwrite = false
        cachedLibrary = nil
        saveTask?.cancel()

        // Delete library JSON
        try? fileManager.removeItem(at: libraryFileURL)

        // Delete all downloaded episode files and cached episodes
        let docs = documentsDirectory()
        if let files = try? fileManager.contentsOfDirectory(atPath: docs.path) {
            for file in files where file.hasPrefix("download_") || file.hasPrefix("cache_") {
                try? fileManager.removeItem(at: docs.appendingPathComponent(file))
            }
        }
    }
}
