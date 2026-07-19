import AVFoundation
import CoreML
import FluidAudio
import Foundation

enum ParakeetBenchmark {
    private static let feedChunkSamples = 1_280 // 80 ms at 16 kHz

    static func run(
        audio: CanonicalBenchmarkAudio,
        cacheURL: URL,
        reference: String?,
        feedMode: FeedMode
    ) async throws -> BenchmarkResult {
        try FileManager.default.createDirectory(
            at: cacheURL,
            withIntermediateDirectories: true
        )

        let modelConfiguration = MLModelConfiguration()
        modelConfiguration.computeUnits = .cpuAndNeuralEngine
        let manager = StreamingUnifiedAsrManager(
            configuration: modelConfiguration,
            config: UnifiedConfig(leftFrames: 70, chunkFrames: 2, rightFrames: 2),
            encoderPrecision: .int8
        )

        let loadStart = uptimeNanoseconds()
        try await manager.loadModels(
            to: cacheURL,
            configuration: nil,
            progressHandler: nil
        )
        let loadMs = elapsedMilliseconds(from: loadStart)

        let warmupStart = uptimeNanoseconds()
        let warmupAudio = CanonicalBenchmarkAudio(samples: Array(repeating: 0, count: 6_400))
        try await manager.appendAudio(warmupAudio.pcmBuffer(range: 0..<warmupAudio.samples.count))
        try await manager.processBufferedAudio()
        _ = try await manager.finish()
        try await manager.reset()
        let warmupMs = elapsedMilliseconds(from: warmupStart)

        let recorder = PartialEventRecorder()
        await manager.setPartialTranscriptCallback { text in
            recorder.record(text: text)
        }

        let resourceStart = ResourceUsage.current()
        let streamStart = uptimeNanoseconds()
        recorder.reset(startNanoseconds: streamStart)
        var processingNanoseconds: UInt64 = 0
        var maximumFeedLagMs = 0
        var offset = 0

        while offset < audio.samples.count {
            let end = min(offset + feedChunkSamples, audio.samples.count)
            if feedMode == .realtime {
                let scheduled = streamStart
                    + UInt64((Double(end) / Double(CanonicalBenchmarkAudio.sampleRate)) * 1_000_000_000)
                let now = uptimeNanoseconds()
                if scheduled > now {
                    try await Task.sleep(nanoseconds: scheduled - now)
                }
                maximumFeedLagMs = max(
                    maximumFeedLagMs,
                    elapsedMilliseconds(from: scheduled, to: uptimeNanoseconds())
                )
            }

            let buffer = try audio.pcmBuffer(range: offset..<end)
            try await manager.appendAudio(buffer)
            let processStart = uptimeNanoseconds()
            try await manager.processBufferedAudio()
            processingNanoseconds += uptimeNanoseconds() - processStart
            offset = end
        }

        let logicalRelease = feedMode == .realtime
            ? streamStart + UInt64(Double(audio.samples.count) / 16_000 * 1_000_000_000)
            : uptimeNanoseconds()
        let finishStart = uptimeNanoseconds()
        let transcript = try await manager.finish()
        let finalTimestamp = uptimeNanoseconds()
        processingNanoseconds += finalTimestamp - finishStart
        let resources = ResourceUsage.current().delta(from: resourceStart)
        let partials = recorder.snapshot()
        await manager.cleanup()

        return makeResult(
            engine: .parakeetUnified320,
            engineVersion: "FluidAudio 0.15.5",
            model: "Parakeet Unified int8 [70,2,2]",
            modelLicense: "CC-BY-4.0",
            computeBackend: "Core ML CPU + Apple Neural Engine",
            feedMode: feedMode,
            audio: audio,
            modelLoadMs: loadMs,
            warmupMs: warmupMs,
            firstPartialMs: partials.firstPartialMs,
            partialIntervalsMs: partials.intervalsMs,
            releaseToFinalMs: elapsedMilliseconds(from: logicalRelease, to: finalTimestamp),
            inferenceWorkMs: Int((processingNanoseconds + 999_999) / 1_000_000),
            maximumFeedLagMs: maximumFeedLagMs,
            transcript: transcript,
            reference: reference,
            resources: resources
        )
    }
}
