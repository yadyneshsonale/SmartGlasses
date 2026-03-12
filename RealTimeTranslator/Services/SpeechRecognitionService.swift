import Foundation
import AVFoundation
import Speech
import Combine

/// Manages real-time speech recognition using AVAudioEngine and the Speech Framework.
class SpeechRecognitionService: ObservableObject {

    @Published var recognizedText: String = ""
    @Published var isListening: Bool = false
    @Published var error: String?

    private var audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    // MARK: - Permissions
    func requestPermissions() async -> Bool {
        let micStatus = await requestMicrophonePermission()
        let speechStatus = await requestSpeechPermission()
        return micStatus && speechStatus
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    // MARK: - Start Listening
    func startListening(locale: Locale) {
        // Cancel any existing task
        stopListening()

        speechRecognizer = SFSpeechRecognizer(locale: locale)
        speechRecognizer?.defaultTaskHint = .dictation

        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            self.error = "Speech recognizer unavailable for this language"
            return
        }

        do {
            try configureAudioSession()
            try startAudioEngine()
            isListening = true
            error = nil
        } catch {
            self.error = error.localizedDescription
            isListening = false
        }
    }

    private func configureAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func startAudioEngine() throws {
        // Remove any existing tap first
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true

        // Use on-device recognition if available (offline support)
        if #available(iOS 13, *) {
            recognitionRequest?.requiresOnDeviceRecognition = false // set true for pure offline
        }

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Check if format is valid (simulator may return invalid format)
        guard recordingFormat.sampleRate > 0 && recordingFormat.channelCount > 0 else {
            throw NSError(domain: "SpeechRecognition", code: -1, 
                          userInfo: [NSLocalizedDescriptionKey: "Microphone not available. Please use a physical device or check simulator audio settings."])
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest!) { [weak self] result, error in
            DispatchQueue.main.async {
                if let result = result {
                    self?.recognizedText = result.bestTranscription.formattedString
                }
                if let error = error as NSError? {
                    // Code 1110 = end of utterance — not a real error
                    if error.code != 1110 {
                        self?.error = error.localizedDescription
                    }
                }
            }
        }
    }

    // MARK: - Stop Listening
    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil

        try? AVAudioSession.sharedInstance().setActive(false)
        isListening = false
    }
}
