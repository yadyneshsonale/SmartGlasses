import Foundation

/// Thread-safe FIFO queue for outgoing translated audio frames to Raspberry Pi
/// Supports concurrent producer (TranslationWorker) and consumer (NetworkSender)
actor OutgoingAudioBuffer {
    
    // MARK: - Properties
    
    private var buffer: [Data] = []
    private let maxBufferSize: Int
    private var totalFramesSent: Int = 0
    
    /// Current number of frames in buffer
    var count: Int {
        buffer.count
    }
    
    /// Whether buffer is empty
    var isEmpty: Bool {
        buffer.isEmpty
    }
    
    /// Total frames that have been dequeued
    var sentFrames: Int {
        totalFramesSent
    }
    
    /// Estimated buffer duration in milliseconds
    var estimatedDurationMs: Int {
        // TTS output frames vary, estimate ~50ms per frame average
        buffer.count * 50
    }
    
    // MARK: - Initialization
    
    /// Initialize buffer with max size
    /// - Parameter maxSize: Maximum number of frames to hold
    init(maxSize: Int = 20) {
        self.maxBufferSize = maxSize
    }
    
    // MARK: - Operations
    
    /// Enqueue translated audio frame (FIFO)
    func enqueue(_ data: Data) {
        // For outgoing, we may want to block or drop if full
        // For now, allow growth but warn
        if buffer.count >= maxBufferSize {
            // Drop oldest to make room
            buffer.removeFirst()
        }
        buffer.append(data)
    }
    
    /// Enqueue multiple frames at once
    func enqueueAll(_ frames: [Data]) {
        for frame in frames {
            enqueue(frame)
        }
    }
    
    /// Dequeue first audio frame (FIFO)
    /// Returns nil if buffer is empty
    func dequeue() -> Data? {
        guard !buffer.isEmpty else { return nil }
        totalFramesSent += 1
        return buffer.removeFirst()
    }
    
    /// Dequeue up to N frames at once
    func dequeueBatch(maxCount: Int) -> [Data] {
        let count = min(maxCount, buffer.count)
        guard count > 0 else { return [] }
        
        let batch = Array(buffer.prefix(count))
        buffer.removeFirst(count)
        totalFramesSent += count
        return batch
    }
    
    /// Peek at first frame without removing
    func peek() -> Data? {
        buffer.first
    }
    
    /// Clear all frames
    func clear() {
        buffer.removeAll()
    }
    
    /// Reset sent counter
    func resetSentCount() {
        totalFramesSent = 0
    }
    
    /// Get buffer statistics
    func getStats() -> OutgoingBufferStats {
        OutgoingBufferStats(
            frameCount: buffer.count,
            maxSize: maxBufferSize,
            totalSent: totalFramesSent,
            estimatedDurationMs: estimatedDurationMs
        )
    }
}

// MARK: - Buffer Statistics

struct OutgoingBufferStats {
    let frameCount: Int
    let maxSize: Int
    let totalSent: Int
    let estimatedDurationMs: Int
    
    var utilizationPercent: Double {
        guard maxSize > 0 else { return 0 }
        return Double(frameCount) / Double(maxSize) * 100
    }
}
