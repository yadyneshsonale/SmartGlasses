import Foundation
import AVFoundation
import Speech

/// Background worker that processes the streaming translation pipeline
/// Continuously receives audio, performs streaming STT, translates, and generates TTS
@MainActor
class TranslationWorker: ObservableObject {
    
    // MARK: - Published State
    
    @Published var workerStatus: WorkerStatus = .idle
    @Published var processedFrameCount: Int = 0
    @Published var lastRecognizedText: String = ""
    @Published var lastTranslatedText: String = ""
    @Published var lastError: String?
    @Published var currentPartialText: String = ""
    
    // MARK: - Properties
    
    private let incomingBuffer: IncomingAudioBuffer
    private let outgoingBuffer: OutgoingAudioBuffer
    private let translationService: TranslationService
    private let ttsService: TTSService
    
    private var workerTask: Task<Void, Never>?
    private var speechRecognizer: SFSpeechRecognizer?
    
    // Streaming recognition state
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var isRecognitionActive: Bool = false
    private var isSpeaking: Bool = false
    
    // Sentence detection
    private var lastFinalText: String = ""
    private var silenceTimer: Task<Void, Never>?
    private let silenceThresholdMs: UInt64 = 1_500_000_000 // 1.5 seconds of no new text = end of utterance
    
    /// Source language for speech recognition
    var sourceLanguage: TranslationLanguage = .english
    
    /// Target language for translation and TTS
    var targetLanguage: TranslationLanguage = .spanish
    
    /// Audio format for incoming PCM data (16-bit mono 16kHz)
    private let incomingFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 16000,
        channels: 1,
        interleaved: true
    )!
    
    // MARK: - Worker Status
    
    enum WorkerStatus: Equatable {
        case idle
        case running
        case listening
        case processing
        case translating
        case synthesizing
        case error(String)
        
        var displayText: String {
            switch self {
            case .idle: return "Idle"
            case .running: return "Running"
            case .listening: return "Listening..."
            case .processing: return "Processing Speech"
            case .translating: return "Translating"
            case .synthesizing: return "Generating Speech"
            case .error(let msg): return "Error: \(msg)"
            }
        }
        
        var isActive: Bool {
            switch self {
            case .running, .listening, .processing, .translating, .synthesizing: return true
            default: return false
            }
        }
    }
    
    // MARK: - Initialization
    
    init(incomingBuffer: IncomingAudioBuffer, 
         outgoingBuffer: OutgoingAudioBuffer,
         translationService: TranslationService) {
        self.incomingBuffer = incomingBuffer
        self.outgoingBuffer = outgoingBuffer
        self.translationService = translationService
        self.ttsService = TTSService()
    }
    
    // MARK: - Worker Control
    
    /// Start the streaming translation worker
    func start() {
        guard workerTask == nil else { return }
        
        // Initialize speech recognizer for source language
        speechRecognizer = SFSpeechRecognizer(locale: sourceLanguage.locale)
        
        workerStatus = .running
        
        // Start the main audio processing loop
        workerTask = Task { [weak self] in
            await self?.runStreamingLoop()
        }
    }
    
    /// Stop the translation worker
    func stop() {
        workerTask?.cancel()
        workerTask = nil
        
        silenceTimer?.cancel()
        silenceTimer = nil
        
        stopRecognition()
        
        workerStatus = .idle
    }
    
    // MARK: - Streaming Recognition Loop
    
    /// Main streaming loop - continuously processes audio from jitter buffer
    private func runStreamingLoop() async {
        while !Task.isCancelled {
            // Ensure recognition is started
            if !isRecognitionActive {
                await startStreamingRecognition()
            }
            
            // Feed audio from jitter buffer to recognizer
            await feedAudioToRecognizer()
            
            // Small delay to prevent busy-waiting
            try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
        }
        
        stopRecognition()
        workerStatus = .idle
    }
    
    /// Start a new streaming recognition session
    private func startStreamingRecognition() async {
        guard let speechRecognizer = speechRecognizer,
              speechRecognizer.isAvailable else {
            workerStatus = .error("Speech recognizer unavailable")
            return
        }
        
        // Create new recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        guard let request = recognitionRequest else { return }
        
        // Configure for streaming
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        
        // Add any task hints for better recognition
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        
        isRecognitionActive = true
        workerStatus = .listening
        lastFinalText = ""
        currentPartialText = ""
        
        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                await self?.handleRecognitionResult(result: result, error: error)
            }
        }
    }
    
    /// Handle recognition results (partial and final)
    private func handleRecognitionResult(result: SFSpeechRecognitionResult?, error: Error?) async {
        if let error = error {
            // Check if it's a normal end (e.g., silence or manual stop)
            let nsError = error as NSError
            if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110 {
                // Recognition ended normally, process any remaining text
                if !lastFinalText.isEmpty {
                    await processCompletedSpeech(lastFinalText)
                }
            } else {
                lastError = error.localizedDescription
                print("[TranslationWorker] Recognition error: \(error)")
            }
            
            // Restart recognition
            isRecognitionActive = false
            return
        }
        
        guard let result = result else { return }
        
        let transcription = result.bestTranscription.formattedString
        currentPartialText = transcription
        workerStatus = .processing
        
        // Reset silence timer on new text
        resetSilenceTimer()
        
        if result.isFinal {
            // Final result - process the complete utterance
            lastRecognizedText = transcription
            lastFinalText = ""
            currentPartialText = ""
            
            await processCompletedSpeech(transcription)
            
            // Recognition task completed, restart for next utterance
            isRecognitionActive = false
        } else {
            // Partial result - update UI and track for silence detection
            lastFinalText = transcription
        }
    }
    
    /// Reset the silence detection timer
    private func resetSilenceTimer() {
        silenceTimer?.cancel()
        
        silenceTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.silenceThresholdMs ?? 1_500_000_000)
            
            guard !Task.isCancelled else { return }
            
            // Silence detected - end current recognition and process
            await MainActor.run {
                Task { @MainActor [weak self] in
                    await self?.handleSilenceDetected()
                }
            }
        }
    }
    
    /// Handle silence detection - end current speech segment
    private func handleSilenceDetected() async {
        guard !lastFinalText.isEmpty else { return }
        
        let textToProcess = lastFinalText
        lastFinalText = ""
        currentPartialText = ""
        
        // End current recognition and force a restart so we don't keep feeding audio
        // into an ended request (which can stall the pipeline after the first utterance).
        stopRecognition()

        // Process the speech
        await processCompletedSpeech(textToProcess)
    }
    
    /// Feed audio from jitter buffer to the recognizer
    private func feedAudioToRecognizer() async {
        guard let request = recognitionRequest, isRecognitionActive else { return }
        
        // Get audio frame from jitter buffer
        guard let audioData = await incomingBuffer.popFrameForSTT() else { return }
        
        processedFrameCount += 1
        
        // Convert to AVAudioPCMBuffer
        guard let pcmBuffer = pcmBufferFromData(audioData) else { return }
        
        // Append to recognition request
        request.append(pcmBuffer)
    }
    
    /// Stop current recognition session
    private func stopRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
        
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        
        isRecognitionActive = false
    }
    
    // MARK: - Speech Processing Pipeline
    
    /// Process completed speech: translate and speak on phone
    private func processCompletedSpeech(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        lastRecognizedText = text
        
        // 1. Translate
        workerStatus = .translating
        let translatedText = await translate(text: text)
        lastTranslatedText = translatedText
        
        guard !translatedText.isEmpty else {
            workerStatus = .listening
            return
        }
        
        // 2. Speak on phone speaker
        workerStatus = .synthesizing
        isSpeaking = true

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            ttsService.speak(text: translatedText, language: targetLanguage.bcp47Code) {
                continuation.resume()
            }
        }

        isSpeaking = false
        workerStatus = .listening
    }
    
    // MARK: - PCM Conversion
    
    /// Convert raw PCM data to AVAudioPCMBuffer
    private func pcmBufferFromData(_ data: Data) -> AVAudioPCMBuffer? {
        // Calculate frame count (16-bit = 2 bytes per sample)
        let frameCount = UInt32(data.count / 2)
        
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: incomingFormat, frameCapacity: frameCount) else {
            return nil
        }
        
        buffer.frameLength = frameCount
        
        // Copy PCM data into buffer
        data.withUnsafeBytes { rawBufferPointer in
            if let baseAddress = rawBufferPointer.baseAddress {
                memcpy(buffer.int16ChannelData![0], baseAddress, data.count)
            }
        }
        
        return buffer
    }
    
    // MARK: - Translation
    
    /// Translate text from source to target language
    private func translate(text: String) async -> String {
        await translationService.translate(
            text: text,
            from: sourceLanguage,
            to: targetLanguage
        )
    }
    
    // MARK: - Configuration
    
    /// Update language settings
    func updateLanguages(source: TranslationLanguage, target: TranslationLanguage) {
        sourceLanguage = source
        targetLanguage = target
        
        // Reinitialize speech recognizer if language changed
        if speechRecognizer?.locale != source.locale {
            speechRecognizer = SFSpeechRecognizer(locale: source.locale)
            
            // Restart recognition with new language
            if isRecognitionActive {
                stopRecognition()
            }
        }
    }
}

// MARK: - Translation Errors

enum TranslationError: Error, LocalizedError {
    case speechRecognizerUnavailable
    case invalidAudioFormat
    case ttsGenerationFailed
    case translationFailed
    
    var errorDescription: String? {
        switch self {
        case .speechRecognizerUnavailable:
            return "Speech recognizer is not available"
        case .invalidAudioFormat:
            return "Invalid audio format"
        case .ttsGenerationFailed:
            return "Text-to-speech generation failed"
        case .translationFailed:
            return "Translation failed"
        }
    }
}
