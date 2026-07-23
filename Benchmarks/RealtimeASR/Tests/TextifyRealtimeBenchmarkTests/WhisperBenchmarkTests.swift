import Foundation
import Testing
@testable import TextifyRealtimeBenchmark

@Test func explicitCatalogModelIDOverridesWhisperFilenameStem() {
    let session = WhisperBenchmarkSession(
        modelURL: URL(fileURLWithPath: "/tmp/ggml-large-v3-q5_0.bin"),
        modelID: "whisper-large-v3-q5_0",
        languageCode: "en",
        feedMode: .accelerated
    )

    #expect(session.modelName == "whisper-large-v3-q5_0")
}
