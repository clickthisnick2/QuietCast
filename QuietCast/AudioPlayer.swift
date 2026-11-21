import AVFoundation
import MediaPlayer
import Observation
import os

@Observable
@MainActor
final class AudioPlayer {
    static let shared = AudioPlayer()

    var currentEpisode: Episode?
    var isPlaying = false
    var isBuffering = false
    /// Set when the current item fails to play. Cleared on the next play attempt.
    var playbackError: String?
    var currentTime: Double = 0
    var duration: Double = 0
    var sleepTimerRemaining: Double? = nil  // seconds remaining, nil = off
    var sleepTimerActive: Bool { sleepTimerRemaining != nil }
    var isScrubbing = false
    var currentSystemVolume: Float { VolumeEnforcer.shared.currentSystemVolume }

    /// The episode list for auto-play next; set when loading a podcast's episodes
    var episodeList: [Episode] = []
    /// The feed URL of the podcast whose episode list is currently loaded
    var currentFeedURL: String?

    private let logger = Logger(subsystem: "com.quietcast", category: "AudioPlayer")
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var silentPlayer: AVPlayer?
    private var endOfEpisodeObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var lastSavedTime: Double = 0
    private var sleepTimerTask: Task<Void, Never>?
    private var reenableTask: Task<Void, Never>?
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?
    private var itemStatusObservation: NSKeyValueObservation?
    private var failedToEndObserver: NSObjectProtocol?
    private var fadeInTask: Task<Void, Never>?

    private init() {
        observeInterruptions()
        observeRouteChanges()
    }

    /// Caps in-app volume while audio is playing. Called when the volume limit changes.
    func clampOutputToMaxVolume() {
        guard isPlaying else { return }
        player?.volume = min(player?.volume ?? 1.0, AppSettings.shared.maxVolume)
    }

    func applyPlaybackRate() {
        if isPlaying {
            player?.rate = AppSettings.shared.playbackRate
        }
        updateNowPlaying()
    }

    /// Lock Volume Range was toggled. Enforce, or arm the auto re-enable timer.
    func systemVolumeLockChanged() {
        if AppSettings.shared.systemVolumeCapEnabled {
            cancelVolumeRangeReenable()
            VolumeEnforcer.shared.enforceSystemVolumeCap()
        } else {
            scheduleVolumeRangeReenableIfNeeded()
        }
    }

    /// If a re-enable was scheduled and its time has passed, turn Lock Volume Range back on.
    func checkVolumeRangeReenableSchedule() {
        guard !AppSettings.shared.systemVolumeCapEnabled,
            let scheduled = AppSettings.shared.volumeRangeReenableAt,
            scheduled <= Date()
        else { return }
        AppSettings.shared.systemVolumeCapEnabled = true
    }

    func scheduleVolumeRangeReenableIfNeeded() {
        let minutes = AppSettings.shared.volumeRangeAutoReenableMinutes
        guard minutes > 0 else {
            cancelVolumeRangeReenable()
            return
        }

        let reenableDate = Date().addingTimeInterval(TimeInterval(minutes * 60))
        AppSettings.shared.volumeRangeReenableAt = reenableDate

        reenableTask?.cancel()
        reenableTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(minutes * 60))
            if Task.isCancelled { return }
            guard let self else { return }
            self.checkVolumeRangeReenableSchedule()
        }
    }

    private func cancelVolumeRangeReenable() {
        reenableTask?.cancel()
        reenableTask = nil
        AppSettings.shared.volumeRangeReenableAt = nil
    }

    func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
        } catch {
            logger.error("Audio session setup failed: \(error.localizedDescription)")
        }
        RemoteCommandHandler.shared.setupRemoteCommands()
        VolumeEnforcer.shared.installVolumeView()
        VolumeEnforcer.shared.observeSystemVolume()
        claimNowPlayingSession()
        checkVolumeRangeReenableSchedule()
    }

    /// Play a silent clip to claim the Now Playing session so headphone commands work immediately.
    private func claimNowPlayingSession() {
        guard let url = Bundle.main.url(forResource: "silence", withExtension: "wav") else { return }
        let silentPlayer = AVPlayer(url: url)
        // Use non-zero volume — the file is silent audio, so the user hears nothing,
        // but iOS requires non-zero volume to register as the Now Playing app.
        silentPlayer.volume = 1.0
        silentPlayer.play()
        self.silentPlayer = silentPlayer

        // Set Now Playing info so the system registers this app as the active player
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = AppSettings.appName
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0
        info[MPMediaItemPropertyPlaybackDuration] = 0
        info[MPNowPlayingInfoPropertyPlaybackRate] = 1.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        // Keep the player alive briefly, then clean up but leave Now Playing info intact
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.silentPlayer = nil
        }
    }

    func play(episode: Episode, rearmAutoPause: Bool = true) {
        playbackError = nil
        let url: URL
        let persistence = PersistenceManager.shared
        if persistence.isDownloaded(episode) {
            url = persistence.localFileURL(for: episode)
        } else {
            guard let streamURL = URL(string: episode.audioURL) else { return }
            url = streamURL
        }

        if currentEpisode?.guid == episode.guid, player != nil {
            resumeCurrentEpisode(armTimer: rearmAutoPause)
            return
        }

        // Save position of the episode we're leaving
        saveCurrentPosition()

        tearDownCurrentItem()
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        player?.volume = 0
        currentEpisode = episode
        isPlaying = true
        isBuffering = true
        if AppSettings.shared.systemVolumeCapEnabled { VolumeEnforcer.shared.enforceSystemVolumeCap() }
        addEndOfEpisodeObserver(for: item)
        observeBufferingStatus()

        // Restore saved position, or apply intro skip for fresh plays
        let savedPosition = PersistenceManager.shared.playbackPosition(for: episode.guid)
        let startPosition: Double
        if savedPosition > 0 {
            startPosition = savedPosition
        } else {
            startPosition = introSkipSeconds()
        }

        beginAudiblePlayback(at: startPosition)
        addTimeObserver()
        updateNowPlaying()
        if rearmAutoPause {
            armAutoPauseTimerIfNeeded()
        }
    }

    func pause() {
        saveCurrentPosition()
        player?.pause()
        isPlaying = false
        updateNowPlaying()
    }

    /// Pause the AVPlayer without saving position (used by speech announcements).
    func pausePlayback() {
        player?.pause()
    }

    /// Resume the AVPlayer at the current playback rate (used by speech announcements).
    func resumePlayback() {
        player?.rate = AppSettings.shared.playbackRate
        armAutoPauseTimerIfNeeded()
    }

    /// Resume the AVPlayer without resetting the sleep timer.
    func resumePlaybackWithoutResettingTimer() {
        player?.rate = AppSettings.shared.playbackRate
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    /// Headset play. Does not pause when audio is already playing.
    func play() {
        guard !isPlaying, currentEpisode != nil else { return }
        // Preserve any in-flight countdown (manual sleep timer or auto-pause).
        // Only arm a fresh timer when no countdown is active.
        resumeCurrentEpisode(armTimer: sleepTimerRemaining == nil)
    }

    /// Fade in the loaded episode, mark it playing, and optionally arm auto-pause.
    private func resumeCurrentEpisode(armTimer: Bool) {
        if let player {
            fadeIn(player: player)
        }
        player?.rate = AppSettings.shared.playbackRate
        isPlaying = true
        if AppSettings.shared.systemVolumeCapEnabled { VolumeEnforcer.shared.enforceSystemVolumeCap() }
        updateNowPlaying()
        if armTimer { armAutoPauseTimerIfNeeded() }
    }

    /// Pause for speech, then run `completion` with whether audio was playing.
    /// Callers that touch player state hop back to the main actor themselves.
    func pauseThenSpeak(_ text: String, identifier: String? = nil, completion: @escaping (_ wasPlaying: Bool) -> Void) {
        let wasPlaying = isPlaying
        if wasPlaying { pausePlayback() }
        SpeechAnnouncer.shared.speak(text, identifier: identifier) {
            completion(wasPlaying)
        }
    }

    // MARK: - Volume

    /// Gentle 1.5-second fade-in
    private func fadeIn(player: AVPlayer) {
        fadeInTask?.cancel()
        player.volume = 0
        let task = Task { @MainActor [weak self] in
            let steps = 15
            let interval = 1.5 / Double(steps)
            for i in 1...steps {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { return }
                player.volume = min(Float(i) / Float(steps), AppSettings.shared.maxVolume)
            }
            if !Task.isCancelled {
                self?.fadeInTask = nil
            }
        }
        fadeInTask = task
    }

    private var isSeeking = false

    func skipForward() {
        // duration stays 0 until the item reports a real length. Clamping to it
        // seeks back to 0:00, so skip from the current time while it is unknown.
        let unclamped = currentTime + Double(AppSettings.skipIntervalSeconds)
        let target = duration > 0 ? min(unclamped, duration) : unclamped
        seek(to: target)
    }

    func skipBackward() {
        seek(to: max(currentTime - Double(AppSettings.skipIntervalSeconds), 0))
    }

    func seek(to time: Double) {
        guard let player else { return }
        currentTime = time
        isSeeking = true
        player.seek(to: CMTimeMakeWithSeconds(time, preferredTimescale: 600)) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isSeeking = false
            }
        }
        updateNowPlaying()
    }

    // MARK: - Sleep Timer

    /// Auto-Pause: arms (or restarts) the timer whenever playback starts or resumes.
    private func armAutoPauseTimerIfNeeded() {
        let minutes = AppSettings.shared.autoPauseMinutes
        guard minutes > 0 else { return }  // Auto-pause off — leave manual timers alone
        setSleepTimer(minutes: minutes)
    }

    func setSleepTimer(minutes: Int) {
        cancelSleepTimer()
        sleepTimerRemaining = Double(minutes * 60)

        sleepTimerTask = Task { [weak self] in
            while let self, let remaining = self.sleepTimerRemaining, remaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
                if Task.isCancelled { return }
                self.sleepTimerRemaining = max(0, remaining - 1)

                // Fade volume in last 30 seconds: from maxVolume down to 0
                if remaining <= 30 {
                    self.player?.volume = AppSettings.shared.maxVolume * Float(remaining / 30.0)
                }

                if remaining <= 1 {
                    self.player?.volume = AppSettings.shared.maxVolume
                    self.pause()
                    self.sleepTimerRemaining = nil
                    return
                }
            }
        }
    }

    func cancelSleepTimer() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
        sleepTimerRemaining = nil
        // Arming auto-pause calls this immediately after fadeIn starts. Restoring
        // max volume here cancels the fade. Leave the ramp alone while it is running.
        if fadeInTask == nil {
            player?.volume = AppSettings.shared.maxVolume
        }
    }

    // MARK: - Time Observer

    private func addTimeObserver() {
        let interval = CMTimeMakeWithSeconds(0.5, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }

                // Always update duration
                if let dur = self.player?.currentItem?.duration, dur.isValid, !dur.isIndefinite {
                    self.duration = CMTimeGetSeconds(dur)
                }

                // Don't overwrite currentTime while seeking or scrubbing
                guard !self.isSeeking && !self.isScrubbing else { return }
                self.currentTime = CMTimeGetSeconds(time)

                // Save position every ~3 seconds of playback
                if abs(self.currentTime - self.lastSavedTime) >= 3 {
                    self.saveCurrentPosition()
                }
            }
        }
    }

    private func removeTimeObserver() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }

    private func tearDownCurrentItem() {
        removeTimeObserver()
        removeEndOfEpisodeObserver()
        clearItemObservations()
    }

    /// Start audible playback immediately, or after seeking to a saved position.
    private func beginAudiblePlayback(at position: Double) {
        guard let player else { return }
        if position > 0 {
            player.seek(to: CMTimeMakeWithSeconds(position, preferredTimescale: 600)) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, let player = self.player else { return }
                    player.rate = AppSettings.shared.playbackRate
                    self.fadeIn(player: player)
                }
            }
        } else {
            player.rate = AppSettings.shared.playbackRate
            fadeIn(player: player)
        }
    }

    // MARK: - End of Episode

    private func addEndOfEpisodeObserver(for item: AVPlayerItem) {
        endOfEpisodeObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleEpisodeFinished()
            }
        }
    }

    private func removeEndOfEpisodeObserver() {
        if let observer = endOfEpisodeObserver {
            NotificationCenter.default.removeObserver(observer)
            endOfEpisodeObserver = nil
        }
    }

    private func handleEpisodeFinished() {
        // Don't close out the episode while the user is dragging the scrubber
        guard !isScrubbing else { return }

        let finishedEpisode = currentEpisode
        saveCurrentPosition()

        // Mark as fully played and reset position so replay starts from the beginning
        if let guid = finishedEpisode?.guid {
            PersistenceManager.shared.markPlayed(guid)
            PersistenceManager.shared.savePlaybackPosition(0, for: guid)
        }

        // Auto-play next episode
        if AppSettings.shared.autoPlayNext, let finished = finishedEpisode,
            let currentIndex = episodeList.firstIndex(where: { $0.guid == finished.guid }),
            currentIndex + 1 < episodeList.count
        {
            let nextEpisode = episodeList[currentIndex + 1]
            tearDownCurrentItem()
            currentEpisode = nil
            player = nil
            play(episode: nextEpisode, rearmAutoPause: false)
            return
        }

        isPlaying = false
        isBuffering = false
        currentTime = 0
        duration = 0
        tearDownCurrentItem()
        currentEpisode = nil
        player = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        cancelSleepTimer()
    }

    // MARK: - Buffering Status

    private func observeBufferingStatus() {
        statusObservation = player?.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isBuffering = player.timeControlStatus == .waitingToPlayAtSpecifiedRate
            }
        }

        itemStatusObservation?.invalidate()
        if let failedToEndObserver {
            NotificationCenter.default.removeObserver(failedToEndObserver)
            self.failedToEndObserver = nil
        }
        guard let item = player?.currentItem else { return }

        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let message = item.error?.localizedDescription
            Task { @MainActor [weak self] in
                self?.handlePlaybackFailure(message)
            }
        }
        failedToEndObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] notification in
            let message = (notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?
                .localizedDescription
            Task { @MainActor [weak self] in
                self?.handlePlaybackFailure(message)
            }
        }
    }

    private func clearItemObservations() {
        statusObservation?.invalidate()
        statusObservation = nil
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        if let failedToEndObserver {
            NotificationCenter.default.removeObserver(failedToEndObserver)
            self.failedToEndObserver = nil
        }
    }

    private func handlePlaybackFailure(_ message: String?) {
        guard currentEpisode != nil else { return }
        isBuffering = false
        isPlaying = false
        player?.pause()
        if playbackError == nil {
            if let message, !message.isEmpty {
                playbackError = message
            } else {
                playbackError = "This episode couldn't be played."
            }
        }
        updateNowPlaying()
    }

    // MARK: - Position Persistence

    private func saveCurrentPosition() {
        guard let episode = currentEpisode, currentTime > 0 else { return }
        lastSavedTime = currentTime
        PersistenceManager.shared.savePlaybackProgress(
            seconds: currentTime,
            guid: episode.guid,
            feedURL: feedURLForCurrentEpisode()
        )
    }

    // MARK: - Intro Skip

    /// Intro skip for the current podcast, or the global default. Returns 0 when skip is off.
    private func introSkipSeconds() -> Double {
        if let feedURL = feedURLForCurrentEpisode() {
            let library = PersistenceManager.shared.loadLibrary()
            if let custom = library.podcastSkipSeconds[feedURL] {
                return Double(custom)
            }
        }
        return Double(AppSettings.shared.defaultSkipIntroSeconds)
    }

    /// Resolve the feed URL for the currently playing episode.
    private func feedURLForCurrentEpisode() -> String? {
        if let feedURL = currentFeedURL {
            return feedURL
        }
        // Fallback: match by podcast title
        let library = PersistenceManager.shared.loadLibrary()
        if let episode = currentEpisode,
            let podcast = library.podcasts.first(where: { $0.title == episode.podcastTitle })
        {
            return podcast.feedURL
        }
        return nil
    }

    // MARK: - Now Playing Info

    private func updateNowPlaying() {
        var info = [String: Any]()
        info[MPMediaItemPropertyTitle] = currentEpisode?.title ?? ""
        info[MPMediaItemPropertyArtist] = currentEpisode?.podcastTitle ?? ""
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPMediaItemPropertyPlaybackDuration] = duration
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? AppSettings.shared.playbackRate : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    // MARK: - Audio Interruptions

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self,
                    let userInfo = notification.userInfo,
                    let rawType = (userInfo[AVAudioSessionInterruptionTypeKey] as? NSNumber)?.uintValue,
                    let type = AVAudioSession.InterruptionType(rawValue: rawType)
                else { return }

                switch type {
                case .began:
                    if self.isPlaying {
                        self.pause()
                    }
                case .ended:
                    let rawOptions = (userInfo[AVAudioSessionInterruptionOptionKey] as? NSNumber)?.uintValue ?? 0
                    let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
                    if options.contains(.shouldResume), self.currentEpisode != nil {
                        self.player?.rate = AppSettings.shared.playbackRate
                        self.isPlaying = true
                        self.updateNowPlaying()
                        self.armAutoPauseTimerIfNeeded()
                    }
                @unknown default:
                    break
                }
            }
        }
    }

    /// Headphones unplugged (or another output removed). iOS pauses playback;
    /// keep the transport in sync so it doesn't stay on the pause icon.
    private func observeRouteChanges() {
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self,
                    let userInfo = notification.userInfo,
                    let rawReason = (userInfo[AVAudioSessionRouteChangeReasonKey] as? NSNumber)?.uintValue,
                    let reason = AVAudioSession.RouteChangeReason(rawValue: rawReason),
                    reason == .oldDeviceUnavailable,
                    self.currentEpisode != nil
                else { return }
                self.isPlaying = false
                self.isBuffering = false
                self.player?.pause()
                self.updateNowPlaying()
            }
        }
    }
}

extension AppSettings {
    /// Point preference changes at playback and the system volume cap.
    /// Called once at launch. The closures run only after a setting actually changes.
    func connectPlaybackReactions() {
        reactions.clampOutputVolume = { AudioPlayer.shared.clampOutputToMaxVolume() }
        reactions.applyPlaybackRate = { AudioPlayer.shared.applyPlaybackRate() }
        reactions.enforceSystemVolumeCap = { VolumeEnforcer.shared.enforceSystemVolumeCap() }
        reactions.enforceSystemVolumeFloor = { VolumeEnforcer.shared.enforceSystemVolumeFloor() }
        reactions.systemVolumeLockChanged = { AudioPlayer.shared.systemVolumeLockChanged() }
        reactions.scheduleVolumeRangeReenable = { AudioPlayer.shared.scheduleVolumeRangeReenableIfNeeded() }
    }
}
