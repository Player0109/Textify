import Foundation
import TextifyConfuciusShim

public enum ConfuciusRuntimeError: Error, Equatable, Sendable {
    case unavailable
    case invalidAudio
    case inferenceFailed
}

/// Native operations run on a dedicated serial queue. Queued operations retain
/// the worker, so final destruction cannot overlap an active native call.
private final class ConfuciusNativeWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "io.github.Player0109.Textify.confucius")
    private var context: OpaquePointer?

    deinit {
        if let context { TextifyConfuciusDestroy(context) }
    }

    func load(library: String, model: String) async throws {
        try await perform { worker in
            if let context = worker.context { TextifyConfuciusDestroy(context) }
            worker.context = TextifyConfuciusCreate(library, model)
            guard worker.context != nil else { throw ConfuciusRuntimeError.unavailable }
        }
    }

    func unload() async {
        try? await perform { worker in
            if let context = worker.context { TextifyConfuciusDestroy(context) }
            worker.context = nil
        }
    }

    func call<T: Sendable>(
        _ operation: @escaping @Sendable (OpaquePointer) throws -> T
    ) async throws -> T {
        try await perform { worker in
            guard let context = worker.context else { throw ConfuciusRuntimeError.unavailable }
            return try operation(context)
        }
    }

    private func perform<T: Sendable>(
        _ operation: @escaping @Sendable (ConfuciusNativeWorker) throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try operation(self) })
            }
        }
    }
}

public actor ConfuciusRuntime {
    private let worker = ConfuciusNativeWorker()
    private let libraryPath: String
    private var generation: UInt64 = 0

    public init(libraryPath: String? = nil) {
        self.libraryPath = libraryPath
            ?? Bundle.main.privateFrameworksURL?
                .appendingPathComponent("libtextify-confucius.dylib").path
            ?? ""
    }

    public func load(modelPath: String) async throws {
        generation &+= 1
        try await worker.load(library: libraryPath, model: modelPath)
        // Warm both paths before admission. Warmup text is discarded.
        _ = try await transcribe(
            TranscriptionAudioBuffer(samples: Array(repeating: 0, count: 8_000)),
            language: "English"
        )
        try await start(language: "English")
        _ = try await push(Array(repeating: 0, count: 5_120))
        _ = try await finish()
    }

    public func unload() async {
        generation &+= 1
        await worker.unload()
    }

    public func transcribe(
        _ audio: TranscriptionAudioBuffer,
        language: String
    ) async throws -> TranscriptionResult {
        guard audio.sampleRate == 16_000, audio.channelCount == 1,
              !audio.samples.isEmpty, audio.samples.count <= 60 * 16_000 else {
            throw ConfuciusRuntimeError.invalidAudio
        }
        let text = try await worker.call { context in
            try audio.samples.withUnsafeBufferPointer { samples in
                guard let value = TextifyConfuciusTranscribe(
                    context, samples.baseAddress, Int32(samples.count), language
                ) else { throw ConfuciusRuntimeError.inferenceFailed }
                return String(cString: value)
            }
        }
        return TranscriptionResult(
            text: text, noSpeechProbability: 0,
            averageLogProbability: 0, compressionRatio: 1
        )
    }

    /// Live text is a preview. Final inference retains edge VAD, optional
    /// cleaning, model-safe windowing, and the existing insertion safeguards.
    public func preview(
        chunks: AsyncStream<TranscriptionAudioBuffer>,
        language: String,
        onText: @escaping @Sendable (String) async -> Void
    ) async throws {
        try Task.checkCancellation()
        generation &+= 1
        let sessionGeneration = generation
        try await start(language: language)
        var pending: [Float] = []
        var completedText = ""
        var currentText = ""
        var windowSamples = 0
        do {
            for await audio in chunks {
                try checkPreviewSession(sessionGeneration)
                guard audio.sampleRate == 16_000, audio.channelCount == 1 else {
                    throw ConfuciusRuntimeError.invalidAudio
                }
                pending.append(contentsOf: audio.samples)
                while pending.count >= 5_120 {
                    try checkPreviewSession(sessionGeneration)
                    let chunk = Array(pending.prefix(5_120))
                    pending.removeFirst(5_120)
                    let delta = try await push(chunk)
                    try checkPreviewSession(sessionGeneration)
                    currentText += delta
                    windowSamples += chunk.count
                    await onText(completedText + currentText)
                    try checkPreviewSession(sessionGeneration)
                    // The upstream stream has a finite positional window.
                    // Keep previews bounded without interrupting microphone capture.
                    if windowSamples >= 25 * 16_000 {
                        let final = try await finish()
                        try checkPreviewSession(sessionGeneration)
                        completedText += final + (final.isEmpty ? "" : " ")
                        currentText = ""
                        windowSamples = 0
                        try await start(language: language)
                    }
                }
            }
        } catch {
            if generation == sessionGeneration {
                _ = try? await worker.call { TextifyConfuciusReset($0) }
            }
            throw error
        }
        if generation == sessionGeneration {
            _ = try? await worker.call { TextifyConfuciusReset($0) }
        }
    }

    private func checkPreviewSession(_ expectedGeneration: UInt64) throws {
        try Task.checkCancellation()
        guard generation == expectedGeneration else { throw CancellationError() }
    }

    private func start(language: String) async throws {
        try await worker.call { context in
            guard TextifyConfuciusStart(context, language) != 0 else {
                throw ConfuciusRuntimeError.inferenceFailed
            }
        }
    }

    private func push(_ samples: [Float]) async throws -> String {
        try await worker.call { context in
            try samples.withUnsafeBufferPointer { buffer in
                guard let text = TextifyConfuciusPush(
                    context, buffer.baseAddress, Int32(buffer.count)
                ) else { throw ConfuciusRuntimeError.inferenceFailed }
                return String(cString: text)
            }
        }
    }

    private func finish() async throws -> String {
        try await worker.call { context in
            guard let text = TextifyConfuciusFinish(context) else {
                throw ConfuciusRuntimeError.inferenceFailed
            }
            return String(cString: text)
        }
    }
}
