import Foundation
import Observation
import os

@Observable
@MainActor
final class DownloadManager {
    static let shared = DownloadManager()

    var activeDownloads: [String: Double] = [:]  // guid -> progress 0..1
    var downloadedGUIDs: Set<String> = []

    /// In-flight tasks, so a download can be cancelled. The GUID also lives on `taskDescription`.
    private var guidToTask: [String: URLSessionDownloadTask] = [:]

    /// Called once the system has delivered background-session events after relaunch.
    var backgroundEventsCompletionHandler: (() -> Void)?

    static let logger = Logger(subsystem: "com.quietcast", category: "DownloadManager")
    private var sessionDelegate: DownloadSessionDelegate!
    private var backgroundSession: URLSession!

    /// Set before `shared` is created when iOS relaunches the app for a background transfer.
    private static var pendingBackgroundCompletion: (() -> Void)?
    private static weak var existing: DownloadManager?

    /// Store the system's completion handler, then make sure the background session exists.
    static func connectBackgroundSession(_ completion: @escaping () -> Void) {
        if let existing {
            existing.backgroundEventsCompletionHandler = completion
        } else {
            pendingBackgroundCompletion = completion
            _ = shared
        }
    }

    private init() {
        let library = PersistenceManager.shared.loadLibrary()
        downloadedGUIDs = library.downloadedEpisodeGUIDs
        PersistenceManager.shared.excludeExistingDownloadsFromBackup()
        Self.sweepIncomingDirectory()

        backgroundEventsCompletionHandler = Self.pendingBackgroundCompletion
        Self.pendingBackgroundCompletion = nil
        Self.existing = self

        sessionDelegate = DownloadSessionDelegate(manager: self)
        let config = URLSessionConfiguration.background(withIdentifier: "com.quietcast.downloads")
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true
        backgroundSession = URLSession(configuration: config, delegate: sessionDelegate, delegateQueue: nil)
        restoreTasksFromSession()
    }

    func isDownloaded(_ episode: Episode) -> Bool {
        downloadedGUIDs.contains(episode.guid) && PersistenceManager.shared.isDownloaded(episode)
    }

    func isDownloading(_ episode: Episode) -> Bool {
        activeDownloads[episode.guid] != nil
    }

    func progress(for episode: Episode) -> Double {
        activeDownloads[episode.guid] ?? 0
    }

    func download(episode: Episode) {
        guard !isDownloaded(episode), !isDownloading(episode) else { return }
        guard let url = URL(string: episode.audioURL) else { return }

        activeDownloads[episode.guid] = 0

        let task = backgroundSession.downloadTask(with: url)
        // Persisted by the background session and still available after relaunch,
        // when the in-memory task map is empty.
        task.taskDescription = episode.guid
        guidToTask[episode.guid] = task
        task.resume()
    }

    func cancelDownload(for episode: Episode) {
        let guid = episode.guid
        guidToTask[guid]?.cancel()
        forgetDownload(guid)
        // Remove any partially written file
        let fileURL = PersistenceManager.shared.localFileURL(for: episode)
        try? FileManager.default.removeItem(at: fileURL)
    }

    func removeDownload(for episode: Episode) {
        let fileURL = PersistenceManager.shared.localFileURL(for: episode)
        try? FileManager.default.removeItem(at: fileURL)
        downloadedGUIDs.remove(episode.guid)
        saveDownloadState()
    }

    /// Cancel any active downloads belonging to a podcast and update in-memory state
    func cancelAllDownloads(for podcast: Podcast) {
        let cachedEpisodes = PersistenceManager.shared.cachedEpisodes(for: podcast.feedURL) ?? []
        let guids = Set(cachedEpisodes.map { $0.guid })

        for guid in guids {
            guidToTask[guid]?.cancel()
            forgetDownload(guid)
        }

        // Also remove GUIDs from the in-memory downloaded set (files are deleted by PersistenceManager)
        downloadedGUIDs.subtract(guids)
    }

    /// Drop in-memory progress and the cancel handle for one episode.
    func forgetDownload(_ guid: String) {
        activeDownloads.removeValue(forKey: guid)
        guidToTask.removeValue(forKey: guid)
    }

    /// GUID from the task description, or from the in-memory task map if the description is missing.
    func guid(for task: URLSessionTask) -> String? {
        if let described = Self.normalizedGUID(task.taskDescription) {
            return described
        }
        return guidToTask.first { $0.value === task }?.key
    }

    /// Cancel all active download tasks and clear tracking state.
    func cancelAllActiveDownloads() {
        for (_, task) in guidToTask {
            task.cancel()
        }
        activeDownloads.removeAll()
        guidToTask.removeAll()
    }

    func saveDownloadState() {
        PersistenceManager.shared.update { library in
            library.downloadedEpisodeGUIDs = downloadedGUIDs
        }
    }

    /// Rebuild the cancel map from tasks the system kept across relaunch.
    private func restoreTasksFromSession() {
        backgroundSession.getAllTasks { [weak self] tasks in
            Task { @MainActor in
                guard let self else { return }
                for task in tasks {
                    guard let guid = Self.normalizedGUID(task.taskDescription),
                        let downloadTask = task as? URLSessionDownloadTask
                    else { continue }
                    self.guidToTask[guid] = downloadTask
                    if self.activeDownloads[guid] == nil {
                        self.activeDownloads[guid] = 0
                    }
                }
            }
        }
    }

    nonisolated fileprivate static func normalizedGUID(_ raw: String?) -> String? {
        let guid = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return guid.isEmpty ? nil : guid
    }

    /// Files moved out of the system download location before we know their destination.
    nonisolated fileprivate static func incomingDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("quietcast-incoming", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Drop leftovers from a previous launch. A finished download is moved to its
    /// final path before the delegate returns, so anything still here is unusable.
    private static func sweepIncomingDirectory() {
        let directory = incomingDirectory()
        guard
            let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
        else { return }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }
}

// MARK: - URLSession Delegate (separate class to avoid @Observable + NSObject conflict)

private class DownloadSessionDelegate: NSObject, URLSessionDownloadDelegate {
    private nonisolated let logger = Logger(subsystem: "com.quietcast", category: "DownloadManager")
    weak var manager: DownloadManager?

    init(manager: DownloadManager) {
        self.manager = manager
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let describedGUID = DownloadManager.normalizedGUID(downloadTask.taskDescription)
        let statusCode = (downloadTask.response as? HTTPURLResponse)?.statusCode
        guard let statusCode, (200...299).contains(statusCode) else {
            logger.error("Not saving download, HTTP status \(statusCode.map(String.init) ?? "missing")")
            Task { @MainActor in
                let guid = describedGUID ?? self.manager?.guid(for: downloadTask)
                guard let guid else { return }
                self.finishTracking(guid: guid, saved: false)
            }
            return
        }
        let fm = FileManager.default

        // The system deletes `location` when this method returns. If we know the
        // episode, move it to the final path now so a relaunch with empty maps
        // still keeps the file. Otherwise park it in our incoming directory.
        if let guid = describedGUID {
            let destURL = PersistenceManager.shared.localFileURL(forEpisodeGUID: guid)
            do {
                try? fm.removeItem(at: destURL)
                try fm.moveItem(at: location, to: destURL)
            } catch {
                logger.error("Failed to save downloaded file for \(guid): \(error.localizedDescription)")
                Task { @MainActor in
                    self.finishTracking(guid: guid, saved: false)
                }
                return
            }
            Task { @MainActor in
                self.finishTracking(guid: guid, saved: true)
            }
            return
        }

        let tempCopy = DownloadManager.incomingDirectory().appendingPathComponent(UUID().uuidString + ".tmp")
        do {
            try fm.moveItem(at: location, to: tempCopy)
        } catch {
            logger.error("Failed to save downloaded file: \(error.localizedDescription)")
            return
        }

        Task { @MainActor in
            let removeTemp = {
                try? FileManager.default.removeItem(at: tempCopy)
            }
            guard let manager = self.manager,
                let guid = manager.guid(for: downloadTask)
            else {
                removeTemp()
                self.logger.error("Download finished with no episode id; deleted temp file")
                return
            }
            let destURL = PersistenceManager.shared.localFileURL(forEpisodeGUID: guid)
            do {
                try? FileManager.default.removeItem(at: destURL)
                try FileManager.default.moveItem(at: tempCopy, to: destURL)
                self.finishTracking(guid: guid, saved: true)
            } catch {
                removeTemp()
                self.finishTracking(guid: guid, saved: false)
                self.logger.error("Failed to move download for \(guid): \(error.localizedDescription)")
            }
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let describedGUID = DownloadManager.normalizedGUID(downloadTask.taskDescription)
        let pct = min(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 1.0)
        Task { @MainActor in
            guard let manager = self.manager else { return }
            let guid = describedGUID ?? manager.guid(for: downloadTask)
            guard let guid else { return }
            manager.activeDownloads[guid] = pct
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard error != nil else { return }
        let describedGUID = DownloadManager.normalizedGUID(task.taskDescription)
        Task { @MainActor in
            guard let manager = self.manager else { return }
            let guid = describedGUID ?? manager.guid(for: task)
            guard let guid else { return }
            manager.forgetDownload(guid)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor in
            // Task scheduled from didFinishDownloadingTo runs first and flushes.
            PersistenceManager.shared.flushToDisk()
            guard let manager = self.manager else { return }
            let handler = manager.backgroundEventsCompletionHandler
            manager.backgroundEventsCompletionHandler = nil
            handler?()
        }
    }

    @MainActor
    private func finishTracking(guid: String, saved: Bool) {
        guard let manager else { return }
        if saved {
            let destURL = PersistenceManager.shared.localFileURL(forEpisodeGUID: guid)
            PersistenceManager.shared.excludeFromBackup(url: destURL)
            manager.downloadedGUIDs.insert(guid)
            manager.saveDownloadState()
            PersistenceManager.shared.flushToDisk()
        }
        manager.forgetDownload(guid)
    }
}
