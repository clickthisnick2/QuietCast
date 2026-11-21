import Foundation
import Observation

/// The only store for preferences. Memory is what the app reads; `didSet` writes the same
/// UserDefaults keys as before so values saved by older builds still load.
@Observable
final class AppSettings {
    /// The user-facing app name. Change this single value to rename the app everywhere.
    static let appName = "QuietCast"

    /// Per-podcast and global Skip Intro menu. `0` is off.
    static let skipIntroOptions = [0, 10, 15, 30, 45, 60, 90, 120]

    /// Skip forward and back, in seconds. Also the remote-command interval.
    static let skipIntervalSeconds = 30

    private let defaults: UserDefaults

    /// Playback and volume reactions. The app installs these at launch. Tests leave them empty.
    struct Reactions {
        var clampOutputVolume: () -> Void = {}
        var applyPlaybackRate: () -> Void = {}
        var enforceSystemVolumeCap: () -> Void = {}
        var enforceSystemVolumeFloor: () -> Void = {}
        var systemVolumeLockChanged: () -> Void = {}
        var scheduleVolumeRangeReenable: () -> Void = {}
    }

    var reactions = Reactions()

    /// False while `init` is copying stored values in. `didSet` must not write or enforce yet.
    private var isReady = false

    private enum Key {
        static let autoPlayNext = "autoPlayNext"
        static let maxVolume = "maxVolume"
        static let systemVolumeCapNC = "systemVolumeCapNC"
        static let systemVolumeFloorNC = "systemVolumeFloorNC"
        static let systemVolumeCapNoNC = "systemVolumeCapNoNC"
        static let systemVolumeFloorNoNC = "systemVolumeFloorNoNC"
        static let noiseCancellationOn = "noiseCancellationOn"
        static let systemVolumeCapEnabled = "systemVolumeCapEnabled"
        static let randomEpisodeAgeDays = "randomEpisodeAgeDays"
        static let randomExcludedFeedURLs = "randomExcludedFeedURLs"
        static let playbackRate = "playbackRate"
        static let volumeRangeAlwaysOn = "volumeRangeAlwaysOn"
        static let volumeRangeAutoReenableMinutes = "volumeRangeAutoReenableMinutes"
        static let volumeRangeReenableAt = "volumeRangeReenableAt"
        static let defaultSkipIntroSeconds = "defaultSkipIntroSeconds"
        static let autoPauseMinutes = "autoPauseMinutes"
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        autoPlayNext = Self.stored(defaults, Key.autoPlayNext, default: true)
        maxVolume = Self.stored(defaults, Key.maxVolume, default: 1.0)
        autoPauseMinutes = Self.stored(defaults, Key.autoPauseMinutes, default: 120)
        noiseCancellationOn = defaults.bool(forKey: Key.noiseCancellationOn)
        systemVolumeCapNC = Self.stored(defaults, Key.systemVolumeCapNC, default: 0.20)
        systemVolumeFloorNC = Self.stored(defaults, Key.systemVolumeFloorNC, default: 0.10)
        systemVolumeCapNoNC = Self.stored(defaults, Key.systemVolumeCapNoNC, default: 0.14)
        systemVolumeFloorNoNC = Self.stored(defaults, Key.systemVolumeFloorNoNC, default: 0.09)
        systemVolumeCapEnabled = Self.stored(defaults, Key.systemVolumeCapEnabled, default: true)
        randomEpisodeAgeDays = Self.stored(defaults, Key.randomEpisodeAgeDays, default: 60)
        randomExcludedFeedURLs = defaults.stringArray(forKey: Key.randomExcludedFeedURLs) ?? []
        playbackRate = Self.stored(defaults, Key.playbackRate, default: 1.0)
        defaultSkipIntroSeconds = Self.stored(defaults, Key.defaultSkipIntroSeconds, default: 0)
        volumeRangeAlwaysOn = Self.stored(defaults, Key.volumeRangeAlwaysOn, default: true)
        volumeRangeAutoReenableMinutes = Self.stored(defaults, Key.volumeRangeAutoReenableMinutes, default: 120)
        volumeRangeReenableAt = defaults.object(forKey: Key.volumeRangeReenableAt) as? Date
        isReady = true
    }

    static let shared = AppSettings(
        defaults: UserDefaults(suiteName: PersistenceManager.appGroupID) ?? .standard
    )

    // MARK: - Playback

    var autoPlayNext: Bool = true {
        didSet { store(autoPlayNext, key: Key.autoPlayNext) }
    }

    var maxVolume: Float = 1.0 {
        didSet {
            guard store(maxVolume, key: Key.maxVolume) else { return }
            onMain { [weak self] in self?.reactions.clampOutputVolume() }
        }
    }

    /// Automatically pause playback after this many minutes (0 = off). Default: 2 hours.
    var autoPauseMinutes: Int = 120 {
        didSet { store(autoPauseMinutes, key: Key.autoPauseMinutes) }
    }

    var playbackRate: Float = 1.0 {
        didSet {
            guard store(playbackRate, key: Key.playbackRate) else { return }
            onMain { [weak self] in self?.reactions.applyPlaybackRate() }
        }
    }

    /// Default number of seconds to skip at the start of each episode (0 = off).
    var defaultSkipIntroSeconds: Int = 0 {
        didSet { store(defaultSkipIntroSeconds, key: Key.defaultSkipIntroSeconds) }
    }

    // MARK: - System Volume

    var noiseCancellationOn: Bool = false {
        didSet {
            guard store(noiseCancellationOn, key: Key.noiseCancellationOn) else { return }
            guard systemVolumeCapEnabled else { return }
            onMain { [weak self] in
                self?.reactions.enforceSystemVolumeCap()
                self?.reactions.enforceSystemVolumeFloor()
            }
        }
    }

    var systemVolumeCapNC: Float = 0.20 {
        didSet {
            guard store(systemVolumeCapNC, key: Key.systemVolumeCapNC) else { return }
            guard noiseCancellationOn && systemVolumeCapEnabled else { return }
            onMain { [weak self] in self?.reactions.enforceSystemVolumeCap() }
        }
    }

    var systemVolumeFloorNC: Float = 0.10 {
        didSet {
            guard store(systemVolumeFloorNC, key: Key.systemVolumeFloorNC) else { return }
            guard noiseCancellationOn && systemVolumeCapEnabled else { return }
            onMain { [weak self] in self?.reactions.enforceSystemVolumeFloor() }
        }
    }

    var systemVolumeCapNoNC: Float = 0.14 {
        didSet {
            guard store(systemVolumeCapNoNC, key: Key.systemVolumeCapNoNC) else { return }
            guard !noiseCancellationOn && systemVolumeCapEnabled else { return }
            onMain { [weak self] in self?.reactions.enforceSystemVolumeCap() }
        }
    }

    var systemVolumeFloorNoNC: Float = 0.09 {
        didSet {
            guard store(systemVolumeFloorNoNC, key: Key.systemVolumeFloorNoNC) else { return }
            guard !noiseCancellationOn && systemVolumeCapEnabled else { return }
            onMain { [weak self] in self?.reactions.enforceSystemVolumeFloor() }
        }
    }

    /// Active cap for the current noise-cancellation mode.
    var systemVolumeCap: Float {
        noiseCancellationOn ? systemVolumeCapNC : systemVolumeCapNoNC
    }

    /// Active floor for the current noise-cancellation mode.
    var systemVolumeFloor: Float {
        noiseCancellationOn ? systemVolumeFloorNC : systemVolumeFloorNoNC
    }

    var systemVolumeCapEnabled: Bool = true {
        didSet {
            guard store(systemVolumeCapEnabled, key: Key.systemVolumeCapEnabled) else { return }
            onMain { [weak self] in self?.reactions.systemVolumeLockChanged() }
        }
    }

    var volumeRangeAlwaysOn: Bool = true {
        didSet {
            guard store(volumeRangeAlwaysOn, key: Key.volumeRangeAlwaysOn) else { return }
            guard volumeRangeAlwaysOn && systemVolumeCapEnabled else { return }
            onMain { [weak self] in
                self?.reactions.enforceSystemVolumeCap()
                self?.reactions.enforceSystemVolumeFloor()
            }
        }
    }

    /// Minutes after disabling Lock Volume Range before it re-enables automatically (0 = off). Default: 2 hours.
    var volumeRangeAutoReenableMinutes: Int = 120 {
        didSet {
            guard store(volumeRangeAutoReenableMinutes, key: Key.volumeRangeAutoReenableMinutes) else { return }
            guard !systemVolumeCapEnabled else { return }
            onMain { [weak self] in self?.reactions.scheduleVolumeRangeReenable() }
        }
    }

    /// When Lock Volume Range is disabled, the date it should automatically re-enable.
    var volumeRangeReenableAt: Date? = nil {
        didSet {
            guard isReady else { return }
            if let volumeRangeReenableAt {
                defaults.set(volumeRangeReenableAt, forKey: Key.volumeRangeReenableAt)
            } else {
                defaults.removeObject(forKey: Key.volumeRangeReenableAt)
            }
        }
    }

    // MARK: - Random Episode

    var randomEpisodeAgeDays: Int = 60 {
        didSet { store(randomEpisodeAgeDays, key: Key.randomEpisodeAgeDays) }
    }

    var randomExcludedFeedURLs: [String] = [] {
        didSet { store(randomExcludedFeedURLs, key: Key.randomExcludedFeedURLs) }
    }

    // MARK: - Persistence

    private static func stored<T>(_ defaults: UserDefaults, _ key: String, default defaultValue: T) -> T {
        defaults.object(forKey: key) as? T ?? defaultValue
    }

    @discardableResult
    private func store(_ value: Bool, key: String) -> Bool {
        guard isReady else { return false }
        defaults.set(value, forKey: key)
        return true
    }

    @discardableResult
    private func store(_ value: Float, key: String) -> Bool {
        guard isReady else { return false }
        defaults.set(value, forKey: key)
        return true
    }

    @discardableResult
    private func store(_ value: Int, key: String) -> Bool {
        guard isReady else { return false }
        defaults.set(value, forKey: key)
        return true
    }

    @discardableResult
    private func store(_ value: [String], key: String) -> Bool {
        guard isReady else { return false }
        defaults.set(value, forKey: key)
        return true
    }

    /// Settings are changed on the main thread. Hop if a write ever arrives elsewhere.
    private func onMain(_ body: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(body)
        } else {
            Task { @MainActor in
                body()
            }
        }
    }
}
