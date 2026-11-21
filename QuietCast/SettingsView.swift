import SwiftUI
import MediaPlayer

struct SettingsView: View {
    var audioPlayer: AudioPlayer { AudioPlayer.shared }
    private var settings: AppSettings { AppSettings.shared }
    @Environment(\.dismiss) private var dismiss
    @State private var showClearAll = false
    @State private var podcasts: [Podcast] = []
    private let reenableOptions = [0, 30, 60, 120, 180]

    private var excludedFeedURLs: Set<String> {
        Set(settings.randomExcludedFeedURLs)
    }

    var body: some View {
        NavigationStack {
            List {
                // Playback
                Section("Playback") {
                    Toggle(
                        isOn: Binding(
                            get: { settings.autoPlayNext },
                            set: { settings.autoPlayNext = $0 }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-Play Next Episode")
                                .font(.subheadline)
                            Text("Plays the next episode when one finishes.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .tint(Color.warmAccent)
                    .padding(.vertical, 4)

                    VolumeLimitRow(
                        title: "Volume Limit",
                        value: settings.maxVolume,
                        range: 0.1...1.0,
                        step: 0.05,
                        caption:
                            "Caps in-app volume. Useful for sleep — keeps audio quiet even if your phone volume is high.",
                        set: { settings.maxVolume = $0 }
                    )
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        OptionMenuRow(
                            title: "Skip Intro",
                            options: AppSettings.skipIntroOptions,
                            selection: settings.defaultSkipIntroSeconds,
                            menuLabel: { $0 == 0 ? "Off" : "\($0) seconds" },
                            capsuleLabel: { $0 == 0 ? "Off" : "\($0)s" }
                        ) { seconds in
                            settings.defaultSkipIntroSeconds = seconds
                        }
                        Text(
                            "Automatically skip the first seconds of each episode. Override per podcast from the episode list toolbar."
                        )
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)

                    AutoPauseRow()
                }

                // System Volume Cap
                Section("System Volume Cap") {
                    Toggle(
                        isOn: Binding(
                            get: { settings.systemVolumeCapEnabled },
                            set: { settings.systemVolumeCapEnabled = $0 }
                        )
                    ) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Lock Volume Range")
                                .font(.subheadline)
                            Text(
                                "Keeps system volume within a set range during nighttime hours (\(TimeGate.nightHoursText))."
                            )
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        }
                    }
                    .tint(Color.warmAccent)
                    .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 8) {
                        OptionMenuRow(
                            title: "Auto Re-Enable",
                            options: reenableOptions,
                            selection: settings.volumeRangeAutoReenableMinutes,
                            menuLabel: minutesChoiceLabel
                        ) { minutes in
                            settings.volumeRangeAutoReenableMinutes = minutes
                        }

                        if !settings.systemVolumeCapEnabled, let reenableAt = settings.volumeRangeReenableAt {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                let remaining = reenableAt.timeIntervalSince(context.date)
                                Text(
                                    remaining > 0
                                        ? "Lock will re-enable in \(PlaybackText.hoursMinutes(remaining.rounded()))"
                                        : "Lock will re-enable now"
                                )
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            }
                        } else {
                            Text(
                                "If you turn off Lock Volume Range, it will automatically turn back on after this delay."
                            )
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 4)

                    if settings.systemVolumeCapEnabled {
                        Toggle(
                            isOn: Binding(
                                get: { settings.volumeRangeAlwaysOn },
                                set: { settings.volumeRangeAlwaysOn = $0 }
                            )
                        ) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Always Enforce")
                                    .font(.subheadline)
                                Text("Also enforce volume range during the day. Turn off to revert to nighttime-only.")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .tint(Color.warmAccent)
                        .padding(.vertical, 4)
                    }

                    if settings.systemVolumeCapEnabled {
                        // Noise Cancellation ON volumes
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Noise Cancellation On", systemImage: "ear.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Color.warmAccent)
                            VolumeLimitRow(
                                title: "Max Volume",
                                value: settings.systemVolumeCapNC,
                                set: { settings.systemVolumeCapNC = $0 }
                            )
                            VolumeLimitRow(
                                title: "Min Volume",
                                value: settings.systemVolumeFloorNC,
                                set: { settings.systemVolumeFloorNC = $0 }
                            )
                        }
                        .padding(.vertical, 4)

                        // Noise Cancellation OFF volumes
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Noise Cancellation Off", systemImage: "ear")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                            VolumeLimitRow(
                                title: "Max Volume",
                                value: settings.systemVolumeCapNoNC,
                                set: { settings.systemVolumeCapNoNC = $0 }
                            )
                            VolumeLimitRow(
                                title: "Min Volume",
                                value: settings.systemVolumeFloorNoNC,
                                set: { settings.systemVolumeFloorNoNC = $0 }
                            )
                            Text(
                                "Toggle noise cancellation mode from the now playing bar. Volume is enforced \(TimeGate.nightHoursText), or always if enabled above."
                            )
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 4)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("System Volume")
                                .font(.subheadline)
                            Spacer()
                            Text("\(Int(audioPlayer.currentSystemVolume * 100))%")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        SystemVolumeSlider()
                            .frame(height: 30)
                        Text("Adjust your device volume directly.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }

                // Random Episode
                Section("Random Episode") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Minimum Age")
                                .font(.subheadline)
                            Spacer()
                            Text("\(settings.randomEpisodeAgeDays) days")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(
                            value: Binding(
                                get: { Double(settings.randomEpisodeAgeDays) },
                                set: { settings.randomEpisodeAgeDays = Int($0) }
                            ),
                            in: 7...365,
                            step: 7
                        )
                        .tint(Color.warmAccent)
                        Text(
                            "The shuffle button on each podcast will only pick episodes older than this many days. Double-press your headphone crown to play a random episode without unlocking your phone."
                        )
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)

                    if !podcasts.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Include in Random")
                                .font(.subheadline)
                            Text("Choose which podcasts the headphone crown random episode draws from.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            ForEach(podcasts) { podcast in
                                Button {
                                    togglePodcast(podcast.feedURL)
                                } label: {
                                    HStack {
                                        Image(
                                            systemName: excludedFeedURLs.contains(podcast.feedURL)
                                                ? "circle" : "checkmark.circle.fill"
                                        )
                                        .foregroundStyle(
                                            excludedFeedURLs.contains(podcast.feedURL) ? .secondary : Color.warmAccent)
                                        Text(podcast.title)
                                            .font(.subheadline)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // How it works — info only
                Section {
                    EmptyView()
                } header: {
                    Text("How \(AppSettings.appName) Works")
                } footer: {
                    VStack(alignment: .leading, spacing: 12) {
                        infoItem(
                            icon: "clock",
                            title: "Search Hours",
                            detail:
                                "Podcast search is available \(TimeGate.searchHoursText). You can always listen to saved podcasts and add feeds by URL."
                        )
                        infoItem(
                            icon: "moon.zzz",
                            title: "Sleep Timer",
                            detail: "Tap the moon icon in the now playing bar. Volume fades out in the last 30 seconds."
                        )
                        infoItem(
                            icon: "timer",
                            title: "Auto-Pause",
                            detail:
                                "Set in Playback settings to automatically pause after a selected duration — default 2 hours."
                        )
                        infoItem(
                            icon: "circle.fill",
                            title: "Warm Display",
                            detail: "Amber tones and dark mode reduce blue light at night."
                        )
                        infoItem(
                            icon: "play.fill",
                            title: "Fade-In",
                            detail: "Audio fades in gently when you press play."
                        )
                        infoItem(
                            icon: "waveform",
                            title: "Voice Quality",
                            detail:
                                "Spoken announcements use your best installed voice. For a more natural sound, go to Settings > Accessibility > Spoken Content > Voices and download a Premium voice."
                        )
                    }
                    .padding(.top, 8)
                }

                // Data
                Section("Data") {
                    Button(role: .destructive) {
                        showClearAll = true
                    } label: {
                        HStack {
                            Text("Clear All Data")
                                .font(.subheadline)
                            Spacer()
                            Image(systemName: "trash")
                                .font(.subheadline)
                        }
                    }
                }

                // About
                Section {
                    HStack {
                        Text("Version")
                            .font(.subheadline)
                        Spacer()
                        Text(appVersion)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("\(AppSettings.appName) — a calm podcast player for bedtime.")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                podcasts = PersistenceManager.shared.loadLibrary().podcasts
            }
            .alert("Clear All Data", isPresented: $showClearAll) {
                Button("Clear Everything", role: .destructive) {
                    clearAllData()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove all podcasts, downloads, and playback history. This cannot be undone.")
            }
        }
    }

    private func infoItem(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(Color.warmAccent)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func togglePodcast(_ feedURL: String) {
        var urls = settings.randomExcludedFeedURLs
        if let index = urls.firstIndex(of: feedURL) {
            urls.remove(at: index)
        } else {
            urls.append(feedURL)
        }
        settings.randomExcludedFeedURLs = urls
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private func clearAllData() {
        AudioPlayer.shared.pause()
        PersistenceManager.shared.clearAllData()
        let dm = DownloadManager.shared
        dm.cancelAllActiveDownloads()
        dm.downloadedGUIDs.removeAll()
        NotificationCenter.default.post(name: .init("QuietCastDataCleared"), object: nil)
    }
}

/// Auto-Pause setting — extracted into its own view to keep the big List
/// lightweight for the Swift compiler.
private struct AutoPauseRow: View {
    private var settings: AppSettings { AppSettings.shared }
    private let options = [0, 15, 30, 45, 60, 90, 120, 180]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            OptionMenuRow(
                title: "Auto-Pause",
                options: options,
                selection: settings.autoPauseMinutes,
                menuLabel: minutesChoiceLabel
            ) { minutes in
                settings.autoPauseMinutes = minutes
            }
            Text(
                "Automatically pauses after the selected duration, even as episodes auto-play overnight. The countdown isn’t reset by new episodes. Unpausing after it fires starts a fresh timer."
            )
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

/// Shared labels for minute menus (auto-pause and lock re-enable).
private func minutesChoiceLabel(_ minutes: Int) -> String {
    switch minutes {
    case 0: return "Off"
    case 60: return "1 hour"
    case 120: return "2 hours"
    case 180: return "3 hours"
    case 15, 30, 45, 90: return "\(minutes) minutes"
    default: return "\(minutes) min"
    }
}

/// Label, tappable percent pill, and slider. Caption is optional.
private struct VolumeLimitRow: View {
    let title: String
    let value: Float
    var range: ClosedRange<Float> = 0.0...1.0
    var step: Float = 0.01
    var caption: String? = nil
    let set: (Float) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                TappablePercentage(
                    value: Binding(get: { value }, set: set),
                    range: range,
                    onCommit: set
                )
            }
            Slider(
                value: Binding(
                    get: { Double(value) },
                    set: { set(Float($0)) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: Double(step)
            )
            .tint(Color.warmAccent)
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// Capsule menu used by Skip Intro, Auto Re-Enable, and Auto-Pause.
private struct OptionMenuRow<Option: Hashable>: View {
    let title: String
    let options: [Option]
    let selection: Option
    let menuLabel: (Option) -> String
    var capsuleLabel: ((Option) -> String)? = nil
    let onSelect: (Option) -> Void

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Menu {
                ForEach(options, id: \.self) { option in
                    Button {
                        onSelect(option)
                    } label: {
                        HStack {
                            Text(menuLabel(option))
                            if selection == option {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Text((capsuleLabel ?? menuLabel)(selection))
                    .font(.subheadline)
                    .foregroundStyle(Color.warmAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.warmAccent.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
    }
}

/// Wraps MPVolumeView as a SwiftUI view — shows the system volume slider.
private struct SystemVolumeSlider: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView()
        // Hide the route button by removing its subview (showsRouteButton is deprecated)
        for subview in view.subviews {
            if subview is UIButton {
                subview.isHidden = true
            }
        }
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

/// Tappable percentage label that flips to a text field for precise input.
private struct TappablePercentage: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    let onCommit: (Float) -> Void

    @State private var isEditing = false
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        if isEditing {
            HStack(spacing: 2) {
                TextField("", text: $text)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 40)
                    .font(.subheadline)
                    .monospacedDigit()
                    .focused($focused)
                    .onAppear {
                        text = "\(Int(value * 100))"
                        focused = true
                    }
                    .onSubmit { commit() }
                Text("%")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Done") { commit() }
                    .font(.caption)
                    .foregroundStyle(Color.warmAccent)
            }
        } else {
            HStack(spacing: 6) {
                Text("tap to edit")
                    .font(.caption2)
                    .foregroundStyle(.quaternary)
                Text("\(Int(value * 100))%")
                    .font(.subheadline)
                    .foregroundStyle(Color.warmAccent)
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.warmAccent.opacity(0.15))
                    .clipShape(Capsule())
            }
            .onTapGesture { isEditing = true }
        }
    }

    private func commit() {
        let parsed = Int(text) ?? Int(value * 100)
        let clamped = Float(min(max(parsed, Int(range.lowerBound * 100)), Int(range.upperBound * 100))) / 100.0
        value = clamped
        onCommit(clamped)
        isEditing = false
        focused = false
    }
}
