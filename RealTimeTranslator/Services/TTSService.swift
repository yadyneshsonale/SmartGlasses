import AVFoundation

/// Wraps AVSpeechSynthesizer for easy text-to-speech playback.
class TTSService: NSObject, AVSpeechSynthesizerDelegate {

    private let synthesizer = AVSpeechSynthesizer()
    private var completionHandler: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Speak
    func speak(text: String, language: String, completion: (() -> Void)? = nil) {
        synthesizer.stopSpeaking(at: .immediate)
        completionHandler = completion

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = bestVoice(for: language)
        utterance.rate = 0.48
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        // Activate audio session so speech is heard over music
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
        try? AVAudioSession.sharedInstance().setActive(true)

        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - Voice Selection
    private func bestVoice(for bcp47: String) -> AVSpeechSynthesisVoice? {
        // Prefer enhanced / premium voice if available
        let voices = AVSpeechSynthesisVoice.speechVoices()
        let langCode = bcp47.lowercased()

        // Try enhanced quality first
        if let enhanced = voices.first(where: {
            $0.language.lowercased().hasPrefix(langCode) &&
            $0.quality == .enhanced
        }) { return enhanced }

        // Fallback to default quality
        if let standard = voices.first(where: {
            $0.language.lowercased().hasPrefix(langCode)
        }) { return standard }

        // Last resort: let the system choose
        return AVSpeechSynthesisVoice(language: bcp47)
    }

    // MARK: - AVSpeechSynthesizerDelegate
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        completionHandler?()
        completionHandler = nil
    }
}
