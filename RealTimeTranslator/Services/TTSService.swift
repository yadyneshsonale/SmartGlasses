import AVFoundation

/// Wraps AVSpeechSynthesizer for easy text-to-speech playback.
class TTSService: NSObject, AVSpeechSynthesizerDelegate {

    private let synthesizer = AVSpeechSynthesizer()
    private var completionHandler: (() -> Void)?
    private var writeCompletionHandler: (() -> Void)?
    private var writeFrameHandler: ((Data) -> Void)?
    private var writeRemainder = Data()
    private var writeConverter: AVAudioConverter?
    private var writeTargetFormat: AVAudioFormat?

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

    // MARK: - Synthesize (PCM frames)
    /// Generates PCM audio frames for network streaming (no local playback).
    /// Output format: 16kHz, 16-bit signed int, mono, interleaved.
    func synthesizePCMFrames(
        text: String,
        language: String,
        frameDurationMs: Double = 20,
        onFrame: @escaping (Data) -> Void,
        completion: (() -> Void)? = nil
    ) {
        synthesizer.stopSpeaking(at: .immediate)
        writeCompletionHandler = completion
        writeFrameHandler = onFrame
        writeRemainder = Data()
        writeConverter = nil

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = bestVoice(for: language)
        utterance.rate = 0.48
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0

        // Target format for Raspberry Pi (PCM16 LE, 16kHz mono)
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        )!
        writeTargetFormat = targetFormat

        let bytesPerFrame = Int(targetFormat.streamDescription.pointee.mBytesPerFrame)
        let framesPerChunk = Int((targetFormat.sampleRate * frameDurationMs) / 1000.0)
        let bytesPerChunk = max(1, framesPerChunk * bytesPerFrame) // ~640 bytes for 20ms

        synthesizer.write(utterance) { [weak self] buffer in
            guard let self else { return }

            guard let pcm = buffer as? AVAudioPCMBuffer else {
                return
            }

            // End-of-stream signal from AVSpeechSynthesizer.write is a 0-frame buffer.
            if pcm.frameLength == 0 {
                if !self.writeRemainder.isEmpty {
                    self.writeFrameHandler?(self.writeRemainder)
                    self.writeRemainder.removeAll(keepingCapacity: true)
                }
                self.writeFrameHandler = nil
                self.writeConverter = nil
                self.writeTargetFormat = nil
                self.writeCompletionHandler?()
                self.writeCompletionHandler = nil
                return
            }

            guard let targetFormat = self.writeTargetFormat else { return }

            if self.writeConverter == nil || self.writeConverter?.inputFormat != pcm.format || self.writeConverter?.outputFormat != targetFormat {
                self.writeConverter = AVAudioConverter(from: pcm.format, to: targetFormat)
            }

            guard let converter = self.writeConverter else { return }

            let inputFrameLength = Int(pcm.frameLength)
            let ratio = targetFormat.sampleRate / pcm.format.sampleRate
            let outCapacity = AVAudioFrameCount(max(1, Int(Double(inputFrameLength) * ratio) + 16))

            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outCapacity) else {
                return
            }

            var didProvideInput = false
            var convertError: NSError?
            converter.convert(to: outBuffer, error: &convertError) { _, outStatus in
                if didProvideInput {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                didProvideInput = true
                outStatus.pointee = .haveData
                return pcm
            }

            if convertError != nil || outBuffer.frameLength == 0 {
                return
            }

            // Extract interleaved PCM16 bytes from the AudioBufferList.
            let abl = outBuffer.audioBufferList.pointee
            let audioBuffer = abl.mBuffers
            guard let mData = audioBuffer.mData, audioBuffer.mDataByteSize > 0 else { return }

            let chunk = Data(bytes: mData, count: Int(audioBuffer.mDataByteSize))
            if !chunk.isEmpty {
                self.writeRemainder.append(chunk)
            }

            // Emit fixed-duration frames for smooth network playback.
            while self.writeRemainder.count >= bytesPerChunk {
                let frame = self.writeRemainder.prefix(bytesPerChunk)
                self.writeRemainder.removeFirst(bytesPerChunk)
                self.writeFrameHandler?(Data(frame))
            }
        }
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
