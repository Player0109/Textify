import Testing
@testable import BenchmarkMetrics

@Test func identicalTextHasZeroWordErrorRate() {
    let result = WordErrorRate.score(
        reference: "Hello, realtime world!",
        hypothesis: "hello realtime world"
    )

    #expect(result.errors == 0)
    #expect(result.rate == 0)
}

@Test func wordErrorRateClassifiesEditOperations() {
    let result = WordErrorRate.score(
        reference: "one two three four",
        hypothesis: "one too three five extra"
    )

    #expect(result.referenceWords == 4)
    #expect(result.hypothesisWords == 5)
    #expect(result.errors == 3)
    #expect(result.substitutions == 2)
    #expect(result.insertions == 1)
    #expect(result.deletions == 0)
}

@Test func characterErrorRateHandlesChineseAndIgnoresPunctuation() {
    let exact = CharacterErrorRate.score(
        reference: "甚至出现交易，几乎停滞。",
        hypothesis: "甚至出现交易几乎停滞"
    )
    #expect(exact.errors == 0)
    #expect(exact.rate == 0)

    let substitution = CharacterErrorRate.score(
        reference: "中文听写",
        hypothesis: "中文听说"
    )
    #expect(substitution.referenceCharacters == 4)
    #expect(substitution.errors == 1)
    #expect(substitution.rate == 0.25)
}
