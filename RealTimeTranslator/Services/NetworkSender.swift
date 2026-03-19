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
    private var reconnectTask: Task<Void, Never>?

    private var currentHost: String = ""
    private var currentPort: Int = 8081
    private let candidatePaths: [String] = ["/audio", "/audio-out"]
    private var activePathIndex: Int = 0
    private var hasSuccessfullySent: Bool = false
    
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

        currentHost = host
        currentPort = port
        activePathIndex = 0
        hasSuccessfullySent = false

        guard let url = makeURL(host: host, port: port, pathIndex: activePathIndex) else {
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

        reconnectTask?.cancel()
        reconnectTask = nil
        
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        
        urlSession?.invalidateAndCancel()
        urlSession = nil
        
        isSending = false
        sendStatus = .idle
        sentPacketCount = 0
        hasSuccessfullySent = false
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
            hasSuccessfullySent = true
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

        // If we haven't successfully sent yet, try an alternate WebSocket path.
        if !hasSuccessfullySent {
            attemptReconnectWithAlternatePath()
        }
    }

    private func makeURL(host: String, port: Int, pathIndex: Int) -> URL? {
        let path = candidatePaths[min(max(pathIndex, 0), candidatePaths.count - 1)]
        return URL(string: "ws://\(host):\(port)\(path)")
    }

    private func attemptReconnectWithAlternatePath() {
        guard activePathIndex + 1 < candidatePaths.count else { return }
        guard !currentHost.isEmpty else { return }

        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self else { return }

            // Brief delay to avoid tight reconnect loops
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }

            self.sendTask?.cancel()
            self.sendTask = nil
            self.webSocket?.cancel(with: .goingAway, reason: nil)
            self.webSocket = nil
            self.urlSession?.invalidateAndCancel()
            self.urlSession = nil

            self.activePathIndex += 1
            guard let url = self.makeURL(host: self.currentHost, port: self.currentPort, pathIndex: self.activePathIndex) else {
                return
            }

            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            self.urlSession = URLSession(configuration: config)

            self.webSocket = self.urlSession?.webSocketTask(with: url)
            self.webSocket?.resume()

            self.sendStatus = .ready
            self.startSendLoop()
        }
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
