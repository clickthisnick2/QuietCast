import AVFoundation
import MediaPlayer
import Observation

/// Manages system volume enforcement: cap, floor, KVO observation, hidden MPVolumeView.
@Observable
@MainActor
final class VolumeEnforcer {
    static let shared = VolumeEnforcer()

    var currentSystemVolume: Float = 0.0

    private var volumeObservation: NSKeyValueObservation?
    private var volumeView: MPVolumeView?
    private var volumeSlider: UISlider?
    private var volumeEnforcementTask: Task<Void, Never>?

    private init() {}

    /// Whether volume enforcement is active: nighttime hours OR always-on override.
    private static var shouldEnforce: Bool {
        TimeGate.isNighttime() || AppSettings.shared.volumeRangeAlwaysOn
    }

    // MARK: - Setup

    /// Install a hidden MPVolumeView in the key window so its UISlider is accessible.
    func installVolumeView() {
        guard volumeView == nil else { return }
        let view = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
        view.alpha = 0.01
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let window = windowScene.windows.first
        {
            window.addSubview(view)
        }
        volumeView = view
        for subview in view.subviews {
            if let slider = subview as? UISlider {
                volumeSlider = slider
                break
            }
        }
    }

    /// Start observing system volume changes via KVO.
    func observeSystemVolume() {
        let session = AVAudioSession.sharedInstance()
        currentSystemVolume = session.outputVolume
        volumeObservation = session.observe(\.outputVolume, options: [.new]) { [weak self] _, change in
            let newVolume = change.newValue ?? session.outputVolume
            Task { @MainActor [weak self] in
                let capEnabled = AppSettings.shared.systemVolumeCapEnabled
                let cap = AppSettings.shared.systemVolumeCap
                let floor = AppSettings.shared.systemVolumeFloor
                if capEnabled && Self.shouldEnforce {
                    if newVolume > cap {
                        self?.volumeSlider?.value = cap
                        self?.startVolumeEnforcement()
                    } else if newVolume < floor {
                        self?.volumeSlider?.value = floor
                        self?.startVolumeEnforcement()
                    }
                }
                self?.currentSystemVolume = newVolume
            }
        }
    }

    // MARK: - Enforcement

    func enforceSystemVolumeCap() {
        guard Self.shouldEnforce else { return }
        let cap = AppSettings.shared.systemVolumeCap
        let current = AVAudioSession.sharedInstance().outputVolume
        if current > cap {
            setSystemVolume(cap)
        }
    }

    func enforceSystemVolumeFloor() {
        guard Self.shouldEnforce else { return }
        let floor = AppSettings.shared.systemVolumeFloor
        let current = AVAudioSession.sharedInstance().outputVolume
        if current < floor {
            setSystemVolume(floor)
        }
    }

    func setSystemVolume(_ volume: Float) {
        if volumeSlider == nil { installVolumeView() }
        volumeSlider?.value = volume
    }

    /// Rapidly enforce the cap for 3 seconds after a violation to catch repeated button presses.
    private func startVolumeEnforcement() {
        volumeEnforcementTask?.cancel()
        volumeEnforcementTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let cap = AppSettings.shared.systemVolumeCap
            let floor = AppSettings.shared.systemVolumeFloor
            for _ in 0..<60 {
                if Task.isCancelled || !Self.shouldEnforce { return }
                let current = AVAudioSession.sharedInstance().outputVolume
                if current > cap {
                    self.volumeSlider?.value = cap
                } else if current < floor {
                    self.volumeSlider?.value = floor
                }
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
    }
}
