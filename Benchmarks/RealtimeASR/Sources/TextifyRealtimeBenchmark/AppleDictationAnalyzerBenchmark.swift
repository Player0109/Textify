@preconcurrency import AVFoundation
import Foundation
import Speech

enum AppleDictationAnalyzerBenchmark {
    private static let feedChunkSamples = 1_280 // 80 ms at 16 kHz

    static func run(
        audio: CanonicalBenchmarkAudio,
        reference: String?,
        feedMode: FeedMode
    ) async throws -> BenchmarkResult {
        guard #available(macOS 26.0, *) else {
            throw BenchmarkCLIError.benchmarkFailed(
                "Apple SpeechAnalyzer requires macOS 26 or newer"
            )
        }
        return try await runAvailable(
            audio: audio,
            reference: reference,
            feedMode: feedMode
        )
    }

    @available(macOS 26.0, *)
    private static func runAvailable(
        audio: CanonicalBenchmarkAudio,
        reference: String?,
        feedMode: FeedMode
    ) async throws -> BenchmarkResult {
        let requestedLocale = Locale(identifier: "en-US")
        guard let locale = await DictationTranscriber.supportedLocale(
            equivalentTo: requestedLocale
        ) else {
            throw BenchmarkCLIError.benchmarkFailed(
                "Apple DictationTranscriber does not support English on this Mac"
            )
        }

        let transcriber = DictationTranscriber(
            locale: locale,
            preset: .progressiveShortDictation
        )
        let analyzer = SpeechAnalyzer(
            modules: [transcriber],
            options: SpeechAnalyzer.Options(
                priority: .userInitiated,
                modelRetention: .processLifetime
            )
        )

        let loadStart = uptimeNanoseconds()
        if await AssetInventory.status(forModules: [transcriber]) != .installed,
           let installation = try await AssetInventory.assetInstallationRequest(
               supporting: [transcriber]
           ) {
            try await installation.downloadAndInstall()
        }
        guard let naturalFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(CanonicalBenchmarkAudio.sampleRate),
            channels: 1,
            interleaved: false
        ), let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber],
            considering: naturalFormat
        ) else {
            throw BenchmarkCLIError.benchmarkFailed(
                "Apple DictationTranscriber did not provide a compatible audio format"
            )
        }
        try await analyzer.prepareToAnalyze(in: analyzerFormat)
        let loadMs = elapsedMilliseconds(from: loadStart)

        let recorder = PartialEventRecorder()
        let resultsTask = Task { () throws -> String in
            var finalized = AttributedString()
            var volatile = AttributedString()
            for try await result in transcriber.results {
                if result.isFinal {
                    finalized.append(result.text)
                    volatile = AttributedString()
                } else {
                    volatile = result.text
                }
                var display = finalized
                display.append(volatile)
                recorder.record(text: String(display.characters))
            }
            return String(finalized.characters)
        }

        let (inputSequence, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        try await analyzer.start(inputSequence: inputSequence)

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

            let workStart = uptimeNanoseconds()
            let buffer = try audio.pcmBuffer(range: offset..<end, format: analyzerFormat)
            inputContinuation.yield(AnalyzerInput(buffer: buffer))
            processingNanoseconds += uptimeNanoseconds() - workStart
            offset = end
        }

        let logicalRelease = feedMode == .realtime
            ? streamStart + UInt64(Double(audio.samples.count) / 16_000 * 1_000_000_000)
            : uptimeNanoseconds()
        inputContinuation.finish()
        let finishStart = uptimeNanoseconds()
        try await analyzer.finalizeAndFinishThroughEndOfInput()
        let transcript = try await resultsTask.value
        let finalTimestamp = uptimeNanoseconds()
        processingNanoseconds += finalTimestamp - finishStart
        let resources = ResourceUsage.current().delta(from: resourceStart)
        let partials = recorder.snapshot()

        return makeResult(
            engine: .appleDictationAnalyzer,
            engineVersion: "Apple Speech framework on macOS 26",
            model: "Apple DictationTranscriber progressive short dictation en-US",
            modelLicense: "Apple system asset; OS license terms",
            computeBackend: "Apple on-device Speech service; hardware backend managed by macOS",
            feedMode: feedMode,
            audio: audio,
            modelLoadMs: loadMs,
            warmupMs: 0,
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
