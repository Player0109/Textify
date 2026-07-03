import TextifyCore
import XCTest

final class PostProcessingTests: XCTestCase {
    func testPunctuationCommandsAndSentenceCapitalizationDoesNotInferProperNouns() {
        let pipeline = PostProcessingPipeline()
        let output = pipeline.process(
            rawText: "hello comma this is textify period new paragraph i am testing",
            replacements: []
        )
        XCTAssertEqual(output, "Hello, this is textify.\n\nI am testing")
    }

    func testVocabularyReplacementCanExplicitlyCapitalizeTextify() {
        let pipeline = PostProcessingPipeline()
        let output = pipeline.process(
            rawText: "hello comma this is textify period",
            replacements: [
                VocabularyReplacement(trigger: "textify", replacement: "Textify")
            ]
        )
        XCTAssertEqual(output, "Hello, this is Textify.")
    }

    func testReplacementSpanIsProtectedFromCapitalization() {
        let pipeline = PostProcessingPipeline()
        let output = pipeline.process(
            rawText: "open player zero one zero nine period",
            replacements: [
                VocabularyReplacement(trigger: "player zero one zero nine", replacement: "Player0109")
            ]
        )
        XCTAssertEqual(output, "Open Player0109.")
    }

    func testHallucinationDiscard() {
        let filter = HallucinationFilter()
        XCTAssertTrue(filter.shouldDiscard(text: "Thanks for watching!", noSpeechProbability: 0.92, averageLogProbability: -1.4, compressionRatio: 2.0))
        XCTAssertFalse(filter.shouldDiscard(text: "Send this note", noSpeechProbability: 0.05, averageLogProbability: -0.2, compressionRatio: 1.1))
    }
}
