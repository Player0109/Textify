import Foundation

final class PartialEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var startNanoseconds: UInt64 = 0
    private var lastText = ""
    private var eventNanoseconds: [UInt64] = []

    func reset(startNanoseconds: UInt64) {
        lock.lock()
        self.startNanoseconds = startNanoseconds
        lastText = ""
        eventNanoseconds = []
        lock.unlock()
    }

    func record(text: String, at timestamp: UInt64 = uptimeNanoseconds()) {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }
        guard normalized != lastText else { return }
        lastText = normalized
        eventNanoseconds.append(timestamp)
    }

    func snapshot() -> (firstPartialMs: Int?, intervalsMs: [Int]) {
        lock.lock()
        defer { lock.unlock() }

        let first = eventNanoseconds.first.map {
            elapsedMilliseconds(from: startNanoseconds, to: $0)
        }
        let intervals = zip(eventNanoseconds, eventNanoseconds.dropFirst()).map {
            elapsedMilliseconds(from: $0.0, to: $0.1)
        }
        return (first, intervals)
    }
}
