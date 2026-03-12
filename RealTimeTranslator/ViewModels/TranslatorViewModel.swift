import Foundation
import Combine
import SwiftUI

// MARK: - Pipeline Status

enum PipelineStatus: Equatable {
    case idle
    case connecting
    case connected
    case receiving
    case translating
    case sending
    case error(String)
    
    var label: String {
        switch self {
        case .idle:         return "Ready to Connect"
        case .connecting:   return "Connecting..."
        case .connected:    return "Connected"
        case .receiving:    return "Receiving Audio"
        case .translating:  return "Translating"
        case .sending:      return "Sending Response"
        case .error(let msg): return "Error: \(msg)"
        }
    }
    
    var color: Color {
        switch self {
        case .idle:         return .gray
        case .connecting:   return .orange
        case .connected:    return .blue
        case .receiving:    return .green
        case .translating:  return .purple
        case .sending:      return .cyan
        case .error:        return .red
        }
    }
    
    var isActive: Bool {
        switch self {
        case .connected, .receiving, .translating, .sending:
            return true
        default:
            return false
        }
    }
}

// MARK: - Pipeline Statistics

struct PipelineStats {
    var incomingBufferSize: Int = 0
    var outgoingBufferSize: Int = 0
    var receivedPackets: Int = 0
    var bytesReceived: Int = 0
    var sentPackets: Int = 0
    var processedFrames: Int = 0
    var droppedFrames: Int = 0
    var latencyMs: Int = 0
    
    var bytesReceivedFormatted: String {
        if bytesReceived < 1024 {
            return "\(bytesReceived) B"
        } else if bytesReceived < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytesReceived) / 1024.0)
        } else {
            return String(format: "%.2f MB", Double(bytesReceived) / (1024.0 * 1024.0))
        }
    }
}

// MARK: - Translator View Model

@MainActor
class TranslatorViewModel: ObservableObject {
    
    // MARK: - Published State
    
    @Published var sourceLanguage: TranslationLanguage = .english
    @Published var targetLanguage: TranslationLanguage = .spanish
    @Published var status: PipelineStatus = .idle
    @Published var stats: PipelineStats = PipelineStats()
    @Published var showPermissionAlert: Bool = false
    @Published var isRunning: Bool = false
    
    // Text display
    @Published var lastRecognizedText: String = ""
    @Published var lastTranslatedText: String = ""
    
    // Connection settings
    @Published var raspberryPiHost: String = "192.168.137.252" {
        didSet {
            if isRunning && oldValue != raspberryPiHost {
                reconnectWithNewSettings()
            }
        }
    }
    @Published var raspberryPiPort: Int = 8080 {
        didSet {
            if isRunning && oldValue != raspberryPiPort {
                reconnectWithNewSettings()
            }
        }
    }
    
    // MARK: - Pipeline Components
    
    private let incomingBuffer = IncomingAudioBuffer(maxSize: 10)
    private let outgoingBuffer = OutgoingAudioBuffer(maxSize: 20)
    private let translationService = TranslationService()
    
    private var networkReceiver: NetworkReceiver?
    private var networkSender: NetworkSender?
    private var translationWorker: TranslationWorker?
    
    private var cancellables = Set<AnyCancellable>()
    private var statsTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    init() {
        setupPipelineComponents()
    }
    
    /// Reconnect when settings change while running
    private func reconnectWithNewSettings() {
        guard isRunning else { return }
        
        // Disconnect and reconnect with new settings
        networkReceiver?.disconnect()
        networkSender?.disconnect()
        
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // Brief delay
            networkReceiver?.connect(host: raspberryPiHost, port: raspberryPiPort)
            networkSender?.connect(host: raspberryPiHost, port: raspberryPiPort + 1)
        }
    }
    
    private func setupPipelineComponents() {
        // Initialize components
        networkReceiver = NetworkReceiver(incomingBuffer: incomingBuffer)
        networkSender = NetworkSender(outgoingBuffer: outgoingBuffer)
        translationWorker = TranslationWorker(
            incomingBuffer: incomingBuffer,
            outgoingBuffer: outgoingBuffer,
            translationService: translationService
        )
        
        // Bind to component state changes
        bindComponents()
    }
    
    private func bindComponents() {
        // Bind NetworkReceiver status
        networkReceiver?.$connectionStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connectionStatus in
                self?.updateStatusFromReceiver(connectionStatus)
            }
            .store(in: &cancellables)
        
        // Bind TranslationWorker status
        translationWorker?.$workerStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] workerStatus in
                self?.updateStatusFromWorker(workerStatus)
            }
            .store(in: &cancellables)
        
        // Bind recognized/translated text
        translationWorker?.$lastRecognizedText
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastRecognizedText)
        
        translationWorker?.$lastTranslatedText
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastTranslatedText)
    }
    
    // MARK: - Status Updates
    
    private func updateStatusFromReceiver(_ connectionStatus: NetworkReceiver.ConnectionStatus) {
        switch connectionStatus {
        case .disconnected:
            if isRunning {
                status = .error("Disconnected")
            } else {
                status = .idle
            }
        case .connecting:
            status = .connecting
        case .connected:
            status = .connected
        case .receiving:
            status = .receiving
        case .reconnecting(let attempt):
            status = .connecting // Show as connecting during reconnect
            print("[ViewModel] Reconnecting attempt \(attempt)")
        case .error(let msg):
            status = .error(msg)
        }
    }
    
    private func updateStatusFromWorker(_ workerStatus: TranslationWorker.WorkerStatus) {
        guard isRunning else { return }
        
        switch workerStatus {
        case .listening:
            status = .receiving // Show as receiving when listening for speech
        case .processing:
            status = .receiving
        case .translating:
            status = .translating
        case .synthesizing:
            status = .sending
        case .error(let msg):
            status = .error(msg)
        default:
            // Keep current status from receiver
            break
        }
    }
    
    // MARK: - Pipeline Control
    
    /// Start the translation pipeline
    func startPipeline() {
        guard !isRunning else { return }
        
        Task {
            // Request speech recognition permission
            let speechGranted = await requestSpeechPermission()
            guard speechGranted else {
                showPermissionAlert = true
                return
            }
            
            isRunning = true
            status = .connecting
            
            // Update worker languages
            translationWorker?.updateLanguages(source: sourceLanguage, target: targetLanguage)
            
            // Start network receiver
            networkReceiver?.connect(host: raspberryPiHost, port: raspberryPiPort)
            
            // Start network sender (same host, different port or same connection)
            networkSender?.connect(host: raspberryPiHost, port: raspberryPiPort + 1)
            
            // Start translation worker
            translationWorker?.start()
            
            // Start stats collection
            startStatsCollection()
        }
    }
    
    /// Stop the translation pipeline
    func stopPipeline() {
        guard isRunning else { return }
        
        isRunning = false
        
        // Stop all components
        translationWorker?.stop()
        networkSender?.disconnect()
        networkReceiver?.disconnect()
        
        // Stop stats collection
        statsTask?.cancel()
        statsTask = nil
        
        // Clear buffers
        Task {
            await incomingBuffer.clear()
            await outgoingBuffer.clear()
        }
        
        status = .idle
        stats = PipelineStats()
    }
    
    /// Toggle pipeline state
    func togglePipeline() {
        if isRunning {
            stopPipeline()
        } else {
            startPipeline()
        }
    }
    
    // MARK: - Language Control
    
    /// Swap source and target languages
    func swapLanguages() {
        let temp = sourceLanguage
        sourceLanguage = targetLanguage
        targetLanguage = temp
        
        // Update worker if running
        translationWorker?.updateLanguages(source: sourceLanguage, target: targetLanguage)
    }
    
    // MARK: - Statistics
    
    private func startStatsCollection() {
        statsTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.collectStats()
                try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            }
        }
    }
    
    private func collectStats() async {
        let incomingStats = await incomingBuffer.getStats()
        let outgoingStats = await outgoingBuffer.getStats()
        
        stats = PipelineStats(
            incomingBufferSize: incomingStats.frameCount,
            outgoingBufferSize: outgoingStats.frameCount,
            receivedPackets: networkReceiver?.receivedPacketCount ?? 0,
            bytesReceived: networkReceiver?.bytesReceived ?? 0,
            sentPackets: networkSender?.sentPacketCount ?? 0,
            processedFrames: translationWorker?.processedFrameCount ?? 0,
            droppedFrames: incomingStats.droppedFrames,
            latencyMs: incomingStats.estimatedDurationMs + outgoingStats.estimatedDurationMs
        )
    }
    
    // MARK: - Permissions
    
    private func requestSpeechPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
    
    // MARK: - Connection Settings
    
    func updateConnectionSettings(host: String, port: Int) {
        raspberryPiHost = host
        raspberryPiPort = port
    }
}

// Import for SFSpeechRecognizer
import Speech
