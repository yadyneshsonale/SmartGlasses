import Foundation

/// Thread-safe FIFO queue for translated utterances to be spoken on device.
/// This decouples translation from playback so the STT loop never "stalls"
/// while the speaker is busy.
actor SpeechOutputQueue {
    private var buffer: [String] = []
    private let maxSize: Int

    init(maxSize: Int = 20) {
        self.maxSize = maxSize
    }

    var isEmpty: Bool { buffer.isEmpty }
    var count: Int { buffer.count }

    func enqueue(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if buffer.count >= maxSize {
            buffer.removeFirst()
        }
        buffer.append(trimmed)
    }

    func dequeue() -> String? {
        guard !buffer.isEmpty else { return nil }
        return buffer.removeFirst()
    }

    func clear() {
        buffer.removeAll()
    }
}

