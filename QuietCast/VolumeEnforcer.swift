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
        TimeGate.isNighttime() || AppSettings.volumeRangeAlwaysOn
    }

    // MARK: - Setup

    /// Install a hidden MPVolumeView in the key window so its UISlider is accessible.
    /// Reattaches when the view was created before a window existed, and looks up the
    /// slider again when the first search missed it.
    func installVolumeView() {
        let view: MPVolumeView
        if let volumeView {
            view = volumeView
        } else {
            let created = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
            created.alpha = 0.01
            volumeView = created
            view = created
        }

        if view.superview == nil || view.window == nil,
           let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            window.addSubview(view)
        }

        if volumeSlider == nil {
            for subview in view.subviews {
                if let slider = subview as? UISlider {
                    volumeSlider = slider
                    break
                }
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
                let capEnabled = AppSettings.systemVolumeCapEnabled
                let cap = AppSettings.systemVolumeCap
                let floor = AppSettings.systemVolumeFloor
                if case .apply(let volume) = VolumePolicy.step(
                    current: newVolume,
                    cap: cap,
                    floor: floor,
                    shouldEnforce: Self.shouldEnforce,
                    capEnabled: capEnabled,
                    cancelled: false
                ) {
                    self?.setSystemVolume(volume)
                    self?.startVolumeEnforcement()
                }
                self?.currentSystemVolume = newVolume
            }
        }
    }

    // MARK: - Enforcement

    func enforceSystemVolumeCap() {
        guard Self.shouldEnforce else { return }
        let cap = AppSettings.systemVolumeCap
        let current = AVAudioSession.sharedInstance().outputVolume
        if current > cap {
            setSystemVolume(cap)
        }
    }

    func enforceSystemVolumeFloor() {
        guard Self.shouldEnforce else { return }
        let floor = AppSettings.systemVolumeFloor
        let current = AVAudioSession.sharedInstance().outputVolume
        if current < floor {
            setSystemVolume(floor)
        }
    }

    func setSystemVolume(_ volume: Float) {
        installVolumeView()
        volumeSlider?.value = volume
    }

    /// Sample the system volume for 3 seconds and pull it back inside the cap and floor.
    /// Used after a volume-button violation, and on open or foreground: the first read can
    /// be stale, and the hidden slider may not be in a window yet.
    func startVolumeEnforcement() {
        volumeEnforcementTask?.cancel()
        volumeEnforcementTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let cap = AppSettings.systemVolumeCap
            let floor = AppSettings.systemVolumeFloor
            for _ in 0..<VolumePolicy.retryCount {
                switch VolumePolicy.step(
                    current: AVAudioSession.sharedInstance().outputVolume,
                    cap: cap,
                    floor: floor,
                    shouldEnforce: Self.shouldEnforce,
                    capEnabled: AppSettings.systemVolumeCapEnabled,
                    cancelled: Task.isCancelled
                ) {
                case .stop:
                    return
                case .unchanged:
                    break
                case .apply(let volume):
                    self.setSystemVolume(volume)
                }
                try? await Task.sleep(nanoseconds: VolumePolicy.retryIntervalNanoseconds)
            }
        }
    }
}
