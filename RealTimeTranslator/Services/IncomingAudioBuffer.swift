import Foundation

/// Thread-safe jitter buffer for incoming audio frames from Raspberry Pi
/// Smooths packet arrival timing and provides ordered PCM data for speech processing
/// Target buffer: 100-200ms of audio (~5-10 frames at 20ms each)
actor IncomingAudioBuffer {
    
    // MARK: - Constants
    
    /// Audio format constants (16kHz, 16-bit mono)
    private let sampleRate: Double = 16000
    private let bytesPerSample: Int = 2
    private let frameDurationMs: Double = 20 // ~640 bytes per frame
    
    /// Jitter buffer targets
    private let targetBufferMs: Double = 150 // Target 150ms buffer
    private let minBufferMs: Double = 100    // Minimum before starving
    private let maxBufferMs: Double = 300    // Maximum before dropping
    
    // MARK: - Properties
    
    private var buffer: [Data] = []
    private var totalBytesBuffered: Int = 0
    private var droppedFrameCount: Int = 0
    private var totalFramesReceived: Int = 0
    
    /// Current number of frames in buffer
    var count: Int {
        buffer.count
    }
    
    /// Whether buffer is empty
    var isEmpty: Bool {
        buffer.isEmpty
    }
    
    /// Total dropped frames due to overflow
    var droppedFrames: Int {
        droppedFrameCount
    }
    
    /// Current buffer duration in milliseconds
    var currentBufferDurationMs: Double {
        // Calculate based on actual bytes (640 bytes = 20ms at 16kHz 16-bit mono)
        let bytesPerMs = (sampleRate * Double(bytesPerSample)) / 1000.0
        return Double(totalBytesBuffered) / bytesPerMs
    }
    
    /// Estimated buffer duration in milliseconds (legacy compatibility)
    var estimatedDurationMs: Int {
        Int(currentBufferDurationMs)
    }
    
    /// Whether buffer has enough data for STT processing
    var isReadyForProcessing: Bool {
        currentBufferDurationMs >= minBufferMs
    }
    
    // MARK: - Initialization
    
    /// Initialize jitter buffer
    /// - Parameter maxSize: Not used directly, buffer managed by duration
    init(maxSize: Int = 10) {
        // maxSize kept for API compatibility but we manage by duration
    }
    
    // MARK: - Operations
    
    /// Append audio chunk to jitter buffer (called by NetworkReceiver)
    /// - Parameter audioChunk: Raw PCM audio data (~640 bytes = 20ms)
    func append(_ audioChunk: Data) {
        totalFramesReceived += 1
        
        // Check if buffer is too full (jitter protection)
        if currentBufferDurationMs >= maxBufferMs {
            // Drop oldest frame to make room
            if let oldest = buffer.first {
                buffer.removeFirst()
                totalBytesBuffered -= oldest.count
                droppedFrameCount += 1
            }
        }
        
        buffer.append(audioChunk)
        totalBytesBuffered += audioChunk.count
    }
    
    /// Legacy enqueue method (calls append)
    func enqueue(_ data: Data) {
        append(data)
    }
    
    /// Pop a single frame for STT processing
    /// - Returns: Audio frame data or nil if buffer is empty
    func popFrameForSTT() -> Data? {
        guard !buffer.isEmpty else { return nil }
        
        let frame = buffer.removeFirst()
        totalBytesBuffered -= frame.count
        return frame
    }
    
    /// Pop all available frames for batch STT processing
    /// - Returns: Array of audio frames
    func popAllFramesForSTT() -> [Data] {
        guard !buffer.isEmpty else { return [] }
        
        let frames = buffer
        buffer.removeAll()
        totalBytesBuffered = 0
        return frames
    }
    
    /// Pop frames up to a target duration
    /// - Parameter targetMs: Maximum duration to pop in milliseconds
    /// - Returns: Combined audio data up to target duration
    func popFrames(upToMs targetMs: Double) -> Data? {
        guard !buffer.isEmpty else { return nil }
        
        var result = Data()
        let bytesPerMs = (sampleRate * Double(bytesPerSample)) / 1000.0
        let targetBytes = Int(targetMs * bytesPerMs)
        
        while !buffer.isEmpty && result.count < targetBytes {
            let frame = buffer.removeFirst()
            totalBytesBuffered -= frame.count
            result.append(frame)
        }
        
        return result.isEmpty ? nil : result
    }
    
    /// Legacy dequeue method (calls popFrameForSTT)
    func dequeue() -> Data? {
        popFrameForSTT()
    }
    
    /// Peek at first frame without removing
    func peek() -> Data? {
        buffer.first
    }
    
    /// Clear all frames
    func clear() {
        buffer.removeAll()
        totalBytesBuffered = 0
    }
    
    /// Reset dropped frame counter
    func resetDroppedCount() {
        droppedFrameCount = 0
    }
    
    /// Get current buffer duration
    func currentBufferDuration() -> TimeInterval {
        currentBufferDurationMs / 1000.0
    }
    
    /// Get buffer statistics
    func getStats() -> BufferStats {
        BufferStats(
            frameCount: buffer.count,
            maxSize: Int(maxBufferMs / frameDurationMs),
            droppedFrames: droppedFrameCount,
            estimatedDurationMs: estimatedDurationMs,
            totalFramesReceived: totalFramesReceived,
            totalBytesBuffered: totalBytesBuffered,
            isReadyForProcessing: isReadyForProcessing
        )
    }
}

// MARK: - Buffer Statistics

struct BufferStats {
    let frameCount: Int
    let maxSize: Int
    let droppedFrames: Int
    let estimatedDurationMs: Int
    var totalFramesReceived: Int = 0
    var totalBytesBuffered: Int = 0
    var isReadyForProcessing: Bool = false
    
    var utilizationPercent: Double {
        guard maxSize > 0 else { return 0 }
        return Double(frameCount) / Double(maxSize) * 100
    }
}
