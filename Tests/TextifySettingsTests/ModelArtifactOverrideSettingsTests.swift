import TextifySettings
import XCTest

final class ModelArtifactOverrideSettingsTests: XCTestCase {
    func testArtifactOverridesDefaultEmptyAndRoundTrip() {
        let store = SettingsStore(storage: .memory)
        var preferences = store.load()

        XCTAssertTrue(
            preferences.modelArtifactOverridesByPurposeCheckpoint.isEmpty
        )

        preferences.modelArtifactOverridesByPurposeCheckpoint[
            "transcription|checkpoint.openai.whisper-large-v3-turbo"
        ] = "whisper-large-v3-turbo-mlx"
        store.save(preferences)

        XCTAssertEqual(
            store.load().modelArtifactOverridesByPurposeCheckpoint[
                "transcription|checkpoint.openai.whisper-large-v3-turbo"
            ],
            "whisper-large-v3-turbo-mlx"
        )
    }
}
