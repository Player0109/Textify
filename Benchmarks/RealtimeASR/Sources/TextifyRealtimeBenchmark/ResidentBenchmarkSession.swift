import Foundation

protocol ResidentBenchmarkSession: AnyObject {
    var engine: BenchmarkEngine { get }
    var modelName: String { get }
    var modelLoadMs: Int { get }
    var warmupMs: Int { get }

    func load() async throws
    func transcribe(
        audio: CanonicalBenchmarkAudio,
        reference: String?
    ) async throws -> BenchmarkResult
    func unload() async
}

enum ResidentBenchmarkSessionFactory {
    static func make(options: BenchmarkOptions) throws -> any ResidentBenchmarkSession {
        switch options.engine {
        case .whisper:
            return WhisperBenchmarkSession(
                modelURL: options.whisperModelURL!,
                languageCode: options.languageCode,
                feedMode: options.feedMode
            )
        case .parakeetTdtV2, .parakeetTdtV3, .parakeetTdtCtc110M,
             .parakeetTdtJapanese:
            return try ParakeetTdtBenchmark.makeSession(
                engine: options.engine,
                modelsRootURL: options.fluidCacheURL,
                feedMode: options.feedMode
            )
        case .reazonSpeechK2V2, .qwen3ASR0_6B, .omnilingualASR300M,
             .dolphinSmall, .senseVoiceSmall:
            return try SherpaOnnxBenchmark.makeSession(
                engine: options.engine,
                runtimeDirectoryURL: options.sherpaRuntimeURL!,
                modelDirectoryURL: options.sherpaModelURL!,
                provider: options.sherpaProvider,
                threadCount: options.sherpaThreadCount,
                languageCode: options.languageCode,
                feedMode: options.feedMode
            )
        case .mlxParakeetRNNT1_1B, .mlxCohereTranscribe03_2026,
             .mlxWhisperLargeV3Turbo, .mlxQwen3ASR0_6B8Bit,
             .mlxQwen3ASR1_7B8Bit, .mlxParakeetTDT0_6BV2,
             .mlxParakeetTDT0_6BV3, .mlxNemotron3_5ASRStreaming0_6B:
            return try MLXAudioBenchmark.makeSession(
                engine: options.engine,
                modelDirectoryURL: options.mlxModelURL!,
                feedMode: options.feedMode
            )
        case .canaryQwen2_5B, .transcribeQwen3ASR0_6B,
             .transcribeQwen3ASR1_7B, .transcribeParakeetTDT0_6BV2,
             .transcribeParakeetTDT0_6BV3, .transcribeNemotron3_5ASRStreaming0_6B:
            return try TranscribeCppBenchmark.makeSession(
                engine: options.engine,
                runtimeDirectoryURL: options.transcribeRuntimeURL!,
                modelURL: options.transcribeModelURL!,
                feedMode: options.feedMode
            )
        default:
            throw BenchmarkCLIError.invalidArguments(
                "Resident batch mode does not support engine: \(options.engine.rawValue)"
            )
        }
    }
}

func runSingleResidentBenchmark(
    session: any ResidentBenchmarkSession,
    audio: CanonicalBenchmarkAudio,
    reference: String?
) async throws -> BenchmarkResult {
    try await session.load()
    do {
        let result = try await session.transcribe(audio: audio, reference: reference)
        await session.unload()
        return result
    } catch {
        await session.unload()
        throw error
    }
}
