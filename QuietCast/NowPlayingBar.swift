import SwiftUI

struct NowPlayingBar: View {
    var audioPlayer: AudioPlayer { AudioPlayer.shared }
    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0

    private let rates: [Float] = [1.0, 1.25, 1.5, 1.75, 2.0]
    private let sleepOptions: [Int] = [15, 30, 45, 60]

    /// The time value shown in the UI — scrub position while dragging, actual time otherwise
    private var displayTime: Double {
        isScrubbing ? scrubValue : audioPlayer.currentTime
    }

    var body: some View {
        VStack(spacing: 2) {
            // Episode title
            Text(audioPlayer.currentEpisode?.title ?? "")
                .font(.caption)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.top, 6)

            if let playbackError = audioPlayer.playbackError {
                Text(playbackError)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }

            // Scrubber
            scrubber

            // Time labels
            HStack {
                Text(PlaybackText.clock(displayTime))
                Spacer()
                Text("-\(PlaybackText.clock(max(audioPlayer.duration - displayTime, 0)))")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .padding(.horizontal)

            // Transport controls
            transportControls
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Scrubber

    private var scrubber: some View {
        Slider(
            value: Binding(
                get: { displayTime },
                set: { newValue in
                    if isScrubbing {
                        scrubValue = newValue
                    }
                }
            ),
            in: 0...max(audioPlayer.duration, 1)
        ) { editing in
            if editing {
                // User started dragging — snapshot current time
                scrubValue = audioPlayer.currentTime
                isScrubbing = true
                audioPlayer.isScrubbing = true
            } else {
                // User released — seek to the scrubbed position
                audioPlayer.seek(to: scrubValue)
                isScrubbing = false
                audioPlayer.isScrubbing = false
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Transport Controls

    private var transportControls: some View {
        HStack(spacing: 20) {
            // Noise cancellation toggle
            if AppSettings.shared.systemVolumeCapEnabled {
                Button {
                    AppSettings.shared.noiseCancellationOn = !AppSettings.shared.noiseCancellationOn
                } label: {
                    Image(systemName: AppSettings.shared.noiseCancellationOn ? "ear.fill" : "ear")
                        .font(.title3)
                        .frame(minWidth: 44, minHeight: 44)
                        .foregroundStyle(AppSettings.shared.noiseCancellationOn ? Color.warmAccent : .secondary)
                }
            }

            // Sleep timer
            if let remaining = audioPlayer.sleepTimerRemaining {
                // Active timer — tap to hear remaining time, long-press for options
                Button {
                    speakSleepTimerRemaining()
                } label: {
                    Text(PlaybackText.countdown(remaining))
                        .font(.caption2)
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.warmDim.opacity(0.25))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    sleepTimerMenuItems()
                }
            } else {
                Menu {
                    sleepTimerMenuItems()
                } label: {
                    Image(systemName: "moon.zzz")
                        .font(.title3)
                        .frame(minWidth: 44, minHeight: 44)
                }
            }

            // Skip back
            Button {
                audioPlayer.skipBackward()
            } label: {
                Image(systemName: "gobackward.\(AppSettings.skipIntervalSeconds)")
                    .font(.title2)
                    .frame(minWidth: 44, minHeight: 44)
            }

            // Play/Pause
            Button {
                if SpeechAnnouncer.shared.isSpeaking {
                    // Stop speech first. If the podcast was playing before speech
                    // (isPlaying stays true while paused for speech), leave it paused
                    // since the button shows "pause". If it wasn't playing, start it.
                    SpeechAnnouncer.shared.stop()
                    if !audioPlayer.isPlaying {
                        audioPlayer.togglePlayPause()
                    }
                } else {
                    audioPlayer.togglePlayPause()
                }
            } label: {
                Image(systemName: audioPlayer.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title)
                    .frame(minWidth: 44, minHeight: 44)
            }

            // Skip forward
            Button {
                audioPlayer.skipForward()
            } label: {
                Image(systemName: "goforward.\(AppSettings.skipIntervalSeconds)")
                    .font(.title2)
                    .frame(minWidth: 44, minHeight: 44)
            }

            // Speed menu
            Menu {
                ForEach(rates, id: \.self) { rate in
                    Button {
                        AppSettings.shared.playbackRate = rate
                    } label: {
                        HStack {
                            Text(PlaybackText.rate(rate))
                            if AppSettings.shared.playbackRate == rate {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text(PlaybackText.rate(AppSettings.shared.playbackRate))
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.2))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Sleep Timer Menu

    @ViewBuilder
    private func sleepTimerMenuItems() -> some View {
        if audioPlayer.sleepTimerActive {
            Button(role: .destructive) {
                audioPlayer.cancelSleepTimer()
            } label: {
                Label("Cancel Timer", systemImage: "xmark")
            }
        }
        ForEach(sleepOptions, id: \.self) { minutes in
            Button {
                audioPlayer.setSleepTimer(minutes: minutes)
            } label: {
                Text("\(minutes) min")
            }
        }
    }

    // MARK: - Speech

    private func speakSleepTimerRemaining() {
        guard let remaining = audioPlayer.sleepTimerRemaining, remaining > 0 else {
            SpeechAnnouncer.shared.speak("No sleep timer is set.")
            return
        }

        // Remember whether the podcast was playing, so we only resume if it was
        audioPlayer.pauseThenSpeak("Sleep timer: \(PlaybackText.spokenRemaining(remaining)).") { wasPlaying in
            if wasPlaying {
                audioPlayer.resumePlaybackWithoutResettingTimer()
            }
        }
    }
}
