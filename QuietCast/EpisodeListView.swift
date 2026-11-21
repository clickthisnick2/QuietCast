import SwiftUI

struct EpisodeListView: View {
    let podcast: Podcast
    var audioPlayer: AudioPlayer { AudioPlayer.shared }
    var downloadManager: DownloadManager { DownloadManager.shared }
    @State private var episodes: [Episode] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var skipIntroSeconds: Int?

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                if isLoading && episodes.isEmpty {
                    ProgressView("Loading episodes…")
                } else if let errorMessage, episodes.isEmpty {
                    ContentUnavailableView(
                        "Failed to Load",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage))
                } else if episodes.isEmpty {
                    ContentUnavailableView(
                        "No Episodes",
                        systemImage: "mic.slash",
                        description: Text("This podcast has no episodes."))
                } else {
                    episodeList
                }
            }
            .frame(maxHeight: .infinity)

            if audioPlayer.currentEpisode != nil {
                NowPlayingBar()
            }
        }
        .navigationTitle(podcast.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    Menu {
                        Button {
                            skipIntroSeconds = nil
                            PersistenceManager.shared.setSkipSeconds(nil, for: podcast.feedURL)
                        } label: {
                            HStack {
                                let d = AppSettings.shared.defaultSkipIntroSeconds
                                Text("Default (\(d == 0 ? "Off" : "\(d)s"))")
                                if skipIntroSeconds == nil {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        ForEach(AppSettings.skipIntroOptions, id: \.self) { seconds in
                            Button {
                                skipIntroSeconds = seconds
                                PersistenceManager.shared.setSkipSeconds(seconds, for: podcast.feedURL)
                            } label: {
                                HStack {
                                    Text(seconds == 0 ? "Off" : "\(seconds)s")
                                    if skipIntroSeconds == seconds {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "forward.end.alt")
                    }

                    Button {
                        playRandomOldEpisode()
                    } label: {
                        Image(systemName: "shuffle")
                    }
                    .disabled(episodes.isEmpty)
                }
            }
        }
        .task {
            skipIntroSeconds = PersistenceManager.shared.skipSeconds(for: podcast.feedURL)
            loadCachedEpisodes()
            await fetchEpisodes()
        }
    }

    private var episodeList: some View {
        List {
            ForEach(episodes) { episode in
                EpisodeRow(episode: episode)
            }

            if audioPlayer.currentEpisode != nil {
                Color.clear
                    .frame(height: 80)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .refreshable {
            await fetchEpisodes()
        }
        .onAppear {
            audioPlayer.episodeList = episodes
            audioPlayer.currentFeedURL = podcast.feedURL
        }
        .onChange(of: episodes) {
            audioPlayer.episodeList = episodes
            audioPlayer.currentFeedURL = podcast.feedURL
        }
    }

    private func playRandomOldEpisode() {
        // Stop any text-to-speech before starting audio
        SpeechAnnouncer.shared.stop()
        let eligible = episodes.olderThan(days: AppSettings.shared.randomEpisodeAgeDays)
        if let random = eligible.randomElement() {
            audioPlayer.play(episode: random)
        }
    }

    private func loadCachedEpisodes() {
        if let cached = PersistenceManager.shared.cachedEpisodes(for: podcast.feedURL) {
            episodes = cached
        }
    }

    private func fetchEpisodes() async {
        defer { isLoading = false }
        do {
            let feed = try await FeedService.load(feedURL: podcast.feedURL)
            if let contentType = feed.contentType, contentType.contains("text/html") {
                if episodes.isEmpty {
                    errorMessage = "This URL returned a webpage, not an RSS feed."
                }
                return
            }
            if !feed.episodes.isEmpty {
                episodes = feed.episodes
                errorMessage = nil
                PersistenceManager.shared.cacheEpisodes(feed.episodes, for: podcast.feedURL)
            } else if episodes.isEmpty {
                errorMessage = "No episodes found. The feed may be empty or in an unsupported format."
            }
        } catch FeedError.invalidURL {
            if episodes.isEmpty {
                errorMessage = "Invalid feed URL."
            }
        } catch FeedError.httpStatus(let code) {
            if episodes.isEmpty {
                errorMessage = "The feed server returned an error (\(code)). Pull to refresh to try again."
            }
        } catch FeedError.notHTTP {
            if episodes.isEmpty {
                errorMessage = "The feed server returned an unexpected response. Pull to refresh to try again."
            }
        } catch FeedError.offline {
            if episodes.isEmpty {
                errorMessage = "No internet connection. Connect to a network and pull to refresh."
            }
        } catch FeedError.timedOut {
            if episodes.isEmpty {
                errorMessage = "The request timed out. Pull to refresh to try again."
            }
        } catch FeedError.other(let message) {
            if episodes.isEmpty {
                errorMessage = message
            }
        } catch {
            if episodes.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct EpisodeRow: View {
    let episode: Episode
    var audioPlayer: AudioPlayer { AudioPlayer.shared }
    var downloadManager: DownloadManager { DownloadManager.shared }
    @State private var showRemoveConfirm = false

    private var isCurrentEpisode: Bool {
        audioPlayer.currentEpisode?.guid == episode.guid
    }

    private var isThisEpisodeSpeaking: Bool {
        SpeechAnnouncer.shared.isSpeaking && SpeechAnnouncer.shared.speakingIdentifier == episode.guid
    }

    private var playbackState: PlaybackState {
        if PersistenceManager.shared.isPlayed(episode.guid) {
            return .played
        }
        let saved = PersistenceManager.shared.playbackPosition(for: episode.guid)
        if saved > 0 {
            return .inProgress(saved)
        }
        return .unplayed
    }

    enum PlaybackState {
        case unplayed
        case inProgress(Double)
        case played
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isCurrentEpisode {
                Label("Now Playing", systemImage: "speaker.wave.2.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.warmAccent)
            }

            Text(episode.title)
                .font(.headline)
                .foregroundColor(isCurrentEpisode ? .warmAccent : .primary)

            HStack(spacing: 4) {
                // Playback status label
                switch playbackState {
                case .unplayed:
                    Text("New")
                        .foregroundStyle(Color.warmAccent)
                case .inProgress(let secs):
                    Text("\(PlaybackText.hoursMinutes(secs)) in")
                        .foregroundStyle(Color.warmAccent)
                case .played:
                    Text("Played")
                        .foregroundStyle(.tertiary)
                }

                if !episode.pubDate.isEmpty {
                    Text("·")
                    Text(episode.pubDate)
                }
                if !episode.duration.isEmpty {
                    Text("·")
                    Text(episode.duration)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !episode.descriptionText.isEmpty {
                Text(episode.descriptionText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            HStack(spacing: 16) {
                // Play/Pause
                if isCurrentEpisode && audioPlayer.isBuffering {
                    ProgressView()
                        .frame(width: 24, height: 24)
                } else {
                    Button {
                        stopSpeakingIfNeeded()
                        if isCurrentEpisode && audioPlayer.isPlaying {
                            audioPlayer.pause()
                        } else {
                            audioPlayer.play(episode: episode)
                        }
                    } label: {
                        Label(
                            isCurrentEpisode && audioPlayer.isPlaying ? "Pause" : "Play",
                            systemImage: isCurrentEpisode && audioPlayer.isPlaying
                                ? "pause.circle.fill" : "play.circle.fill"
                        )
                        .font(.title3)
                    }
                    .buttonStyle(.borderless)
                }

                // Speak episode title + description
                Button {
                    toggleSpeakEpisode()
                } label: {
                    Label(
                        isThisEpisodeSpeaking ? "Speaking…" : "Speak",
                        systemImage: isThisEpisodeSpeaking ? "speaker.wave.3.fill" : "speaker.wave.2"
                    )
                    .font(.caption)
                    .foregroundStyle(isThisEpisodeSpeaking ? Color.warmAccent : Color.secondary)
                }
                .buttonStyle(.borderless)

                Spacer()

                // Download control
                if downloadManager.isDownloaded(episode) {
                    Button {
                        showRemoveConfirm = true
                    } label: {
                        HStack(spacing: 4) {
                            Label("Available Offline", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                            Image(systemName: "xmark")
                                .font(.caption2)
                        }
                        .foregroundStyle(Color.warmGreen)
                    }
                    .buttonStyle(.borderless)
                } else if downloadManager.isDownloading(episode) {
                    HStack(spacing: 8) {
                        ProgressView(value: downloadManager.progress(for: episode))
                            .frame(width: 60)
                        Button {
                            downloadManager.cancelDownload(for: episode)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                    }
                } else {
                    Button {
                        downloadManager.download(episode: episode)
                    } label: {
                        Label("Save Offline", systemImage: "arrow.down.circle")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 4)
        .alert("Remove Download", isPresented: $showRemoveConfirm) {
            Button("Remove", role: .destructive) {
                downloadManager.removeDownload(for: episode)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove the offline copy of this episode? You can download it again later.")
        }
    }

    private func stopSpeakingIfNeeded() {
        guard SpeechAnnouncer.shared.isSpeaking else { return }
        SpeechAnnouncer.shared.stop()
    }

    private func toggleSpeakEpisode() {
        let announcer = SpeechAnnouncer.shared

        // Tapping the same episode again stops it and resumes (if it was playing).
        if isThisEpisodeSpeaking {
            announcer.stop()
            if audioPlayer.isPlaying {
                audioPlayer.resumePlayback()
            }
            return
        }

        // If something else is being spoken, cancel it without resuming yet —
        // we're about to start speaking this episode.
        if announcer.isSpeaking {
            announcer.stop()
        }

        var text = episode.title
        if !episode.descriptionText.isEmpty {
            text += ". " + episode.descriptionText
        }

        // Pause playback so the announcement is audible.
        audioPlayer.pauseThenSpeak(text, identifier: episode.guid) { wasPlaying in
            if wasPlaying {
                self.audioPlayer.resumePlayback()
            }
        }
    }
}
