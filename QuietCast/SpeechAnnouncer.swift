import AVFoundation
import Observation

/// Handles spoken announcements via AVSpeechSynthesizer.
@MainActor
@Observable
final class SpeechAnnouncer {
    static let shared = SpeechAnnouncer()

    private let synthesizer = AVSpeechSynthesizer()
    private let delegate = SpeechAnnouncerDelegate()

    /// Whether speech is currently active.
    private(set) var isSpeaking = false
    /// Identifier of whatever is being spoken (e.g. episode GUID).
    private(set) var speakingIdentifier: String?

    private init() {
        synthesizer.delegate = delegate
    }

    /// Speak a text announcement, then call completion when done.
    func speak(_ text: String, identifier: String? = nil, completion: (() -> Void)? = nil) {
        // Fire the pending callback before replacing it. Crown actions clear
        // isCrownActionActive only inside that callback; dropping it leaves the mutex stuck.
        let replaced = delegate.takePending()
        synthesizer.stopSpeaking(at: .immediate)
        replaced?()

        isSpeaking = true
        speakingIdentifier = identifier

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.volume = min(0.8, AppSettings.shared.maxVolume)
        if let voice = Self.bestAvailableVoice() {
            utterance.voice = voice
        }
        delegate.arm(utterance: utterance, completion: completion)
        synthesizer.speak(utterance)
    }

    /// Stop speech immediately.
    ///
    /// The pending callback is discarded, not fired. Callers of `stop()` decide
    /// whether playback resumes (the Now Playing pause button must not resume).
    /// The crown mutex is cleared here because that callback was the only place
    /// that reset it.
    func stop() {
        _ = delegate.takePending()
        synthesizer.stopSpeaking(at: .immediate)
        markSpeechFinished()
        RemoteCommandHandler.shared.cancelCrownAction()
    }

    /// Called by the delegate when speech finishes naturally.
    func markSpeechFinished() {
        isSpeaking = false
        speakingIdentifier = nil
    }

    /// Find the best quality voice available for the user's language.
    private static func bestAvailableVoice() -> AVSpeechSynthesisVoice? {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let voices = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language == language }
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
        return voices.first
    }
}

/// Delegate that fires a callback when speech finishes.
private class SpeechAnnouncerDelegate: NSObject, AVSpeechSynthesizerDelegate {
    private var onFinish: (() -> Void)?
    private var activeUtterance: AVSpeechUtterance?

    /// Detach the pending callback so a later `didFinish`/`didCancel` cannot run it.
    func takePending() -> (() -> Void)? {
        let callback = onFinish
        onFinish = nil
        activeUtterance = nil
        return callback
    }

    func arm(utterance: AVSpeechUtterance, completion: (() -> Void)?) {
        activeUtterance = utterance
        onFinish = completion
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        fireIfCurrent(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // speak()/stop() clear activeUtterance before calling stopSpeaking, so a cancel
        // of the utterance being replaced does not run the new completion.
        // A system cancel (interruption) still matches and releases the crown mutex.
        fireIfCurrent(utterance)
    }

    private func fireIfCurrent(_ utterance: AVSpeechUtterance) {
        guard utterance === activeUtterance else { return }
        let callback = onFinish
        onFinish = nil
        activeUtterance = nil
        Task { @MainActor in
            SpeechAnnouncer.shared.markSpeechFinished()
        }
        callback?()
    }
}
