import Foundation

/// Receives audio packets from Raspberry Pi over WebSocket
/// Maintains persistent connection with auto-reconnect
/// Pushes received frames into IncomingAudioBuffer
@MainActor
class NetworkReceiver: NSObject, ObservableObject {
    
    // MARK: - Published State
    
    @Published var isConnected: Bool = false
    @Published var connectionStatus: ConnectionStatus = .disconnected
    @Published var receivedPacketCount: Int = 0
    @Published var bytesReceived: Int = 0
    @Published var lastError: String?
    @Published var isAutoReconnecting: Bool = false
    
    // MARK: - Properties
    
    private var webSocket: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private let incomingBuffer: IncomingAudioBuffer
    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    
    /// Current server connection info
    private var currentHost: String = ""
    private var currentPort: Int = 8080
    
    /// Auto-reconnect settings
    private var shouldReconnect: Bool = false
    private var reconnectAttempts: Int = 0
    private let maxReconnectAttempts: Int = 10
    private let reconnectDelay: UInt64 = 2_000_000_000 // 2 seconds
    
    // MARK: - Connection Status
    
    enum ConnectionStatus: Equatable {
        case disconnected
        case connecting
        case connected
        case receiving
        case reconnecting(attempt: Int)
        case error(String)
        
        var displayText: String {
            switch self {
            case .disconnected: return "Disconnected"
            case .connecting: return "Connecting..."
            case .connected: return "Connected"
            case .receiving: return "Receiving Data"
            case .reconnecting(let attempt): return "Reconnecting (\(attempt))..."
            case .error(let msg): return "Error: \(msg)"
            }
        }
        
        var isActive: Bool {
            switch self {
            case .connected, .receiving: return true
            default: return false
            }
        }
    }
    
    // MARK: - Initialization
    
    init(incomingBuffer: IncomingAudioBuffer) {
        self.incomingBuffer = incomingBuffer
        super.init()
    }
    
    // MARK: - Connection Management
    
    /// Connect to Raspberry Pi WebSocket server
    /// - Parameters:
    ///   - host: IP address or hostname of Raspberry Pi
    ///   - port: WebSocket port (default 8080)
    func connect(host: String, port: Int = 8080) {
        // Store connection info for reconnect
        currentHost = host
        currentPort = port
        shouldReconnect = true
        reconnectAttempts = 0
        
        performConnect()
    }
    
    private func performConnect() {
        // Cancel any existing connection
        cleanupConnection()
        
        // Build WebSocket URL
        guard let url = URL(string: "ws://\(currentHost):\(currentPort)/audio") else {
            connectionStatus = .error("Invalid URL")
            lastError = "Invalid URL: \(currentHost):\(currentPort)"
            return
        }
        
        connectionStatus = .connecting
        
        // Create URL session with delegate
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        urlSession = URLSession(configuration: config, delegate: nil, delegateQueue: .main)
        
        // Create WebSocket task
        webSocket = urlSession?.webSocketTask(with: url)
        webSocket?.resume()
        
        // Start continuous receiving loop
        startContinuousReceiving()
        startPingPong()
        
        isConnected = true
        connectionStatus = .connected
        reconnectAttempts = 0
        isAutoReconnecting = false
    }
    
    /// Disconnect from Raspberry Pi (stops auto-reconnect)
    func disconnect() {
        shouldReconnect = false
        reconnectTask?.cancel()
        reconnectTask = nil
        cleanupConnection()
        
        isConnected = false
        connectionStatus = .disconnected
        receivedPacketCount = 0
        bytesReceived = 0
    }
    
    private func cleanupConnection() {
        receiveTask?.cancel()
        receiveTask = nil
        
        pingTask?.cancel()
        pingTask = nil
        
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        
        urlSession?.invalidateAndCancel()
        urlSession = nil
    }
    
    // MARK: - Auto Reconnect
    
    private func scheduleReconnect() {
        guard shouldReconnect, reconnectAttempts < maxReconnectAttempts else {
            if reconnectAttempts >= maxReconnectAttempts {
                connectionStatus = .error("Max reconnect attempts reached")
            }
            return
        }
        
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            guard let self = self else { return }
            
            self.reconnectAttempts += 1
            self.isAutoReconnecting = true
            self.connectionStatus = .reconnecting(attempt: self.reconnectAttempts)
            
            // Exponential backoff: 2s, 4s, 8s... up to 30s
            let delay = min(self.reconnectDelay * UInt64(1 << min(self.reconnectAttempts - 1, 4)), 30_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            
            guard !Task.isCancelled, self.shouldReconnect else { return }
            
            self.performConnect()
        }
    }
    
    // MARK: - Continuous Receiving
    
    private func startContinuousReceiving() {
        receiveTask = Task { [weak self] in
            guard let self = self else { return }
            
            // Continuous receive loop - runs until cancelled or error
            while !Task.isCancelled {
                let shouldContinue = await self.receiveNextMessage()
                if !shouldContinue {
                    break
                }
            }
            
            // Connection lost - try to reconnect if enabled
            if self.shouldReconnect && !Task.isCancelled {
                self.scheduleReconnect()
            }
        }
    }
    
    /// Receive next message from WebSocket
    /// Returns false if connection should be considered dead
    private func receiveNextMessage() async -> Bool {
        guard let webSocket = webSocket else { return false }
        
        do {
            let message = try await webSocket.receive()
            
            switch message {
            case .data(let data):
                await handleAudioData(data)
                return true
                
            case .string(let text):
                handleControlMessage(text)
                return true
                
            @unknown default:
                return true
            }
        } catch {
            return handleReceiveError(error)
        }
    }
    
    /// Process received audio data
    private func handleAudioData(_ data: Data) async {
        // Update stats
        receivedPacketCount += 1
        bytesReceived += data.count
        
        // Update status to show we're actively receiving
        if connectionStatus == .connected {
            connectionStatus = .receiving
        }
        
        // Validate and enqueue audio frame
        // PCM 16-bit mono 16kHz, 20-40ms = 640-1280 bytes
        // Allow wider range for flexibility
        guard data.count >= 64 && data.count <= 65536 else {
            return // Invalid frame, skip
        }
        
        await incomingBuffer.enqueue(data)
    }
    
    private func handleControlMessage(_ text: String) {
        // Handle JSON control messages from Raspberry Pi
        // e.g., {"type": "config", "sampleRate": 16000}
        print("[NetworkReceiver] Control message: \(text)")
    }
    
    /// Handle receive error
    /// Returns true if should continue receiving, false if connection is dead
    private func handleReceiveError(_ error: Error) -> Bool {
        let nsError = error as NSError
        
        // Ignore cancellation - we're intentionally stopping
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return false
        }
        
        // Connection closed/reset errors
        if nsError.code == 57 || nsError.code == 54 || nsError.code == -1005 {
            connectionStatus = .disconnected
            isConnected = false
            lastError = "Connection lost"
            return false // Trigger reconnect
        }
        
        // WebSocket protocol error - connection is dead
        if nsError.domain == "NSPOSIXErrorDomain" {
            connectionStatus = .error("Connection reset")
            isConnected = false
            return false
        }
        
        // Other errors - log but continue trying
        lastError = error.localizedDescription
        connectionStatus = .error(error.localizedDescription)
        return false
    }
    
    // MARK: - Ping/Pong
    
    private func startPingPong() {
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                await self?.sendPing()
            }
        }
    }
    
    private func sendPing() async {
        webSocket?.sendPing { [weak self] error in
            if let error = error {
                Task { @MainActor in
                    self?.lastError = "Ping failed: \(error.localizedDescription)"
                }
            }
        }
    }
    
    // MARK: - Send Control Messages
    
    /// Send configuration to Raspberry Pi
    func sendConfiguration(_ config: [String: Any]) async {
        guard let webSocket = webSocket,
              let jsonData = try? JSONSerialization.data(withJSONObject: config),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return
        }
        
        do {
            try await webSocket.send(.string(jsonString))
        } catch {
            lastError = "Failed to send config: \(error.localizedDescription)"
        }
    }
}
