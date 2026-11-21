import MediaPlayer

/// Configures MPRemoteCommandCenter handlers and manages crown action state.
@MainActor
final class RemoteCommandHandler {
    static let shared = RemoteCommandHandler()

    /// Prevents concurrent crown actions (double-press and triple-press).
    private(set) var isCrownActionActive = false

    /// Release the crown mutex without running the speech completion.
    /// Used when speech is stopped and that completion is discarded.
    func cancelCrownAction() {
        isCrownActionActive = false
    }

    private init() {}

    func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        let skipInterval = NSNumber(value: AppSettings.skipIntervalSeconds)

        addCommand(center.playCommand) {
            AudioPlayer.shared.play()
        }
        addCommand(center.pauseCommand) {
            AudioPlayer.shared.pause()
        }
        addCommand(center.togglePlayPauseCommand) {
            AudioPlayer.shared.togglePlayPause()
        }

        center.skipForwardCommand.preferredIntervals = [skipInterval]
        addCommand(center.skipForwardCommand) {
            AudioPlayer.shared.skipForward()
        }
        center.skipBackwardCommand.preferredIntervals = [skipInterval]
        addCommand(center.skipBackwardCommand) {
            AudioPlayer.shared.skipBackward()
        }

        // Double-press crown/AirPods plays a random old episode
        addCommand(center.nextTrackCommand) { [weak self] in
            self?.playRandomOldEpisode()
        }
        // Triple-press crown/AirPods speaks the current time
        addCommand(center.previousTrackCommand) { [weak self] in
            self?.speakCurrentTime()
        }
    }

    private func addCommand(_ command: MPRemoteCommand, action: @escaping @MainActor () -> Void) {
        command.addTarget { _ in
            Task { @MainActor in
                action()
            }
            return .success
        }
    }

    /// Speak the current time aloud, pausing audio during speech.
    func speakCurrentTime() {
        guard !isCrownActionActive else { return }
        isCrownActionActive = true
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let timeString = formatter.string(from: Date())
        AudioPlayer.shared.pauseThenSpeak("The time is \(timeString)") { [weak self] wasPlaying in
            Task { @MainActor [weak self] in
                self?.isCrownActionActive = false
                if wasPlaying { AudioPlayer.shared.resumePlayback() }
            }
        }
    }

    /// Pick a random episode using fair podcast rotation, then play it.
    func playRandomOldEpisode() {
        guard !isCrownActionActive else { return }
        isCrownActionActive = true
        let ageDays = AppSettings.shared.randomEpisodeAgeDays
        let excludedFeedURLs = Set(AppSettings.shared.randomExcludedFeedURLs)

        let persistence = PersistenceManager.shared
        let library = persistence.loadLibrary()

        // Get included podcast feed URLs
        let includedFeedURLs = Set(
            library.podcasts
                .map(\.feedURL)
                .filter { !excludedFeedURLs.contains($0) })

        // Clean rotation: remove feed URLs no longer in the included set
        var rotation = library.crownPodcastRotation.filter { includedFeedURLs.contains($0) }

        // If rotation is empty, start a new shuffled round
        if rotation.isEmpty {
            rotation = Array(includedFeedURLs).shuffled()
        }

        // Walk the rotation to find a podcast with eligible episodes
        var selectedEpisode: Episode?
        var selectedFeedURL: String?
        while !rotation.isEmpty {
            let feedURL = rotation.removeFirst()
            guard let episodes = persistence.cachedEpisodes(for: feedURL) else { continue }
            if let episode = episodes.olderThan(days: ageDays).randomElement() {
                selectedEpisode = episode
                selectedFeedURL = feedURL
                break
            }
        }

        // Save updated rotation
        persistence.update { library in
            library.crownPodcastRotation = rotation
        }

        guard let random = selectedEpisode else {
            isCrownActionActive = false
            return
        }
        AudioPlayer.shared.pauseThenSpeak("\(random.podcastTitle). \(random.title)") { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isCrownActionActive = false
                AudioPlayer.shared.currentFeedURL = selectedFeedURL
                AudioPlayer.shared.play(episode: random)
            }
        }
    }
}
