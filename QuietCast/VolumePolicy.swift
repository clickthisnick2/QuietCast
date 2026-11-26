import Foundation

/// Cap and floor decision for the system-volume retry loop.
/// UIKit-free so `swift test` can cover it. `VolumeEnforcer` applies the result.
enum VolumePolicy {
    /// Samples in the verify-and-retry loop. 60 × 50 ms is the existing 3 second window.
    static let retryCount = 60
    static let retryIntervalNanoseconds: UInt64 = 50_000_000

    /// What one sample of the enforcement loop should do.
    enum Step {
        /// Enforcement is off, or the task was cancelled. Leave the slider alone.
        case stop
        /// Reading is already inside the floor...cap range. Keep sampling; do not write.
        case unchanged
        /// Write this value to the hidden system volume slider.
        case apply(Float)
    }

    /// Decide one sample.
    /// An in-range reading is `.unchanged`, not `.stop`: `outputVolume` can be stale
    /// just after the audio session activates, so the caller keeps sampling until the
    /// retry window ends or enforcement turns off.
    static func step(
        current: Float,
        cap: Float,
        floor: Float,
        shouldEnforce: Bool,
        capEnabled: Bool,
        cancelled: Bool
    ) -> Step {
        if cancelled || !shouldEnforce || !capEnabled {
            return .stop
        }
        if current > cap {
            return .apply(cap)
        }
        if current < floor {
            return .apply(floor)
        }
        return .unchanged
    }
}
