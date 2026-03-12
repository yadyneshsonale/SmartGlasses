import Foundation

/// Sends translated audio packets back to Raspberry Pi over WebSocket
/// Continuously dequeues from OutgoingAudioBuffer and transmits
@MainActor
class NetworkSender: ObservableObject {
    
    // MARK: - Published State
    
    @Published var isSending: Bool = false
    @Published var sentPacketCount: Int = 0
    @Published var sendStatus: SendStatus = .idle
    @Published var lastError: String?
    
    // MARK: - Properties
    
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let outgoingBuffer: OutgoingAudioBuffer
    private var sendTask: Task<Void, Never>?
    
    /// Target send rate in packets per second
    private let targetSendRate: Int = 50 // ~20ms per packet
    
    // MARK: - Send Status
    
    enum SendStatus: Equatable {
        case idle
        case connecting
        case ready
        case sending
        case error(String)
        
        var displayText: String {
            switch self {
            case .idle: return "Idle"
            case .connecting: return "Connecting..."
            case .ready: return "Ready"
            case .sending: return "Sending Response"
            case .error(let msg): return "Error: \(msg)"
            }
        }
    }
    
    // MARK: - Initialization
    
    init(outgoingBuffer: OutgoingAudioBuffer) {
        self.outgoingBuffer = outgoingBuffer
    }
    
    // MARK: - Connection Management
    
    /// Connect to Raspberry Pi for sending translated audio
    /// - Parameters:
    ///   - host: IP address or hostname
    ///   - port: WebSocket port (default 8081 for separate send channel)
    func connect(host: String, port: Int = 8081) {
        guard webSocket == nil else { return }
        
        guard let url = URL(string: "ws://\(host):\(port)/audio-out") else {
            sendStatus = .error("Invalid URL")
            return
        }
        
        sendStatus = .connecting
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        urlSession = URLSession(configuration: config)
        
        webSocket = urlSession?.webSocketTask(with: url)
        webSocket?.resume()
        
        sendStatus = .ready
        startSendLoop()
    }
    
    /// Use existing WebSocket connection (shared with receiver)
    func useExistingConnection(_ socket: URLSessionWebSocketTask) {
        self.webSocket = socket
        sendStatus = .ready
        startSendLoop()
    }
    
    /// Disconnect sender
    func disconnect() {
        sendTask?.cancel()
        sendTask = nil
        
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        
        urlSession?.invalidateAndCancel()
        urlSession = nil
        
        isSending = false
        sendStatus = .idle
        sentPacketCount = 0
    }
    
    // MARK: - Send Loop
    
    private func startSendLoop() {
        isSending = true
        
        sendTask = Task { [weak self] in
            guard let self = self else { return }
            
            while !Task.isCancelled {
                await self.sendNextPacket()
                
                // Rate limiting: ~20ms between sends
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }
    }
    
    private func sendNextPacket() async {
        // Check if buffer has data
        let isEmpty = await outgoingBuffer.isEmpty
        guard !isEmpty else {
            if sendStatus == .sending {
                sendStatus = .ready
            }
            return
        }
        
        // Dequeue and send
        guard let audioData = await outgoingBuffer.dequeue() else { return }
        
        await sendAudioPacket(audioData)
    }
    
    /// Send single audio packet to Raspberry Pi
    private func sendAudioPacket(_ data: Data) async {
        guard let webSocket = webSocket else {
            sendStatus = .error("Not connected")
            return
        }
        
        sendStatus = .sending
        
        do {
            try await webSocket.send(.data(data))
            sentPacketCount += 1
        } catch {
            handleSendError(error)
        }
    }
    
    /// Send batch of audio packets
    func sendBatch(_ packets: [Data]) async {
        for packet in packets {
            await sendAudioPacket(packet)
        }
    }
    
    private func handleSendError(_ error: Error) {
        let nsError = error as NSError
        
        // Ignore cancellation
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return
        }
        
        lastError = error.localizedDescription
        sendStatus = .error(error.localizedDescription)
    }
    
    // MARK: - Control Messages
    
    /// Send status update to Raspberry Pi
    func sendStatusUpdate(_ status: [String: Any]) async {
        guard let webSocket = webSocket,
              let jsonData = try? JSONSerialization.data(withJSONObject: status),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }
        
        do {
            try await webSocket.send(.string(jsonString))
        } catch {
            lastError = "Failed to send status: \(error.localizedDescription)"
        }
    }
}
