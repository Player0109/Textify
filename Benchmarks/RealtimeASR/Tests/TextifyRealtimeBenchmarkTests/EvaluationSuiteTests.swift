import Foundation
import Testing
@testable import BenchmarkMetrics

@Test func evaluationSuiteAcceptsPinnedBalancedManifest() throws {
    let suite = try EvaluationSuiteManifest.decode(Data(validManifest.utf8))

    #expect(suite.id == "english-pr-v1")
    #expect(suite.compatibleItems(maxAudioSeconds: 29).map(\.id) == ["sample-a", "sample-b"])
    #expect(suite.compatibleItems(maxAudioSeconds: 10).map(\.id) == ["sample-a"])
}

@Test func evaluationSuiteRejectsDuplicateItemIDs() {
    let duplicated = validManifest.replacingOccurrences(
        of: "\"id\": \"sample-b\"",
        with: "\"id\": \"sample-a\""
    )

    #expect(throws: EvaluationSuiteValidationError.duplicateItemID("sample-a")) {
        try EvaluationSuiteManifest.decode(Data(duplicated.utf8))
    }
}

@Test func evaluationSuiteRejectsUnsafeAudioPath() {
    let unsafe = validManifest.replacingOccurrences(
        of: "\"audio\": \"sample-a.flac\"",
        with: "\"audio\": \"../sample-a.flac\""
    )

    #expect(throws: EvaluationSuiteValidationError.unsafeAudioPath("../sample-a.flac")) {
        try EvaluationSuiteManifest.decode(Data(unsafe.utf8))
    }
}

@Test func evaluationSuiteAcceptsEmptyReferencesForNoSpeechControls() throws {
    let suite = try EvaluationSuiteManifest.decode(Data(noSpeechManifest.utf8))

    #expect(suite.subsets[0].role == .negativeControl)
    #expect(suite.subsets[0].speechOrigin == .noSpeech)
    #expect(suite.items.allSatisfy { $0.reference.isEmpty })
}

@Test func evaluationSuiteRejectsEmptySpeechReference() {
    let emptyReference = validManifest.replacingOccurrences(
        of: "\"reference\": \"a short reference\"",
        with: "\"reference\": \"\""
    )

    #expect(throws: EvaluationSuiteValidationError.emptyReference("sample-a")) {
        try EvaluationSuiteManifest.decode(Data(emptyReference.utf8))
    }
}

@Test func evaluationSuiteRejectsReferenceTextForNoSpeechControl() {
    let unexpectedReference = noSpeechManifest.replacingOccurrences(
        of: "\"reference\": \"\"",
        with: "\"reference\": \"not silent\"",
        options: [],
        range: noSpeechManifest.range(of: "\"reference\": \"\"")
    )

    #expect(
        throws: EvaluationSuiteValidationError.unexpectedNoSpeechReference("sample-a")
    ) {
        try EvaluationSuiteManifest.decode(Data(unexpectedReference.utf8))
    }
}

@Test func evaluationSuiteRequiresEveryDeclaredDurationBucketPerSubset() {
    let incomplete = validManifest.replacingOccurrences(
        of: itemB,
        with: ""
    )

    #expect(
        throws: EvaluationSuiteValidationError.missingDurationBucket(
            subsetID: "librispeech-clean",
            bucket: .seconds20To29
        )
    ) {
        try EvaluationSuiteManifest.decode(Data(incomplete.utf8))
    }
}

@Test func evaluationSuiteV1StillRejectsRepeatedSubsetBuckets() {
    let repeated = validManifest.replacingOccurrences(
        of: "\n      ]\n    }",
        with: repeatedItem + "\n      ]\n    }"
    )

    #expect(
        throws: EvaluationSuiteValidationError.duplicateDurationBucket(
            subsetID: "librispeech-clean",
            bucket: .seconds1To3
        )
    ) {
        try EvaluationSuiteManifest.decode(Data(repeated.utf8))
    }
}

@Test func evaluationSuiteV2AcceptsRepeatedBucketsAndSliceMetadata() throws {
    let repeated = validManifest
        .replacingOccurrences(of: "\"schemaVersion\": 1", with: "\"schemaVersion\": 2")
        .replacingOccurrences(
            of: "\n      ]\n    }",
            with: repeatedItem + "\n      ]\n    }"
        )

    let suite = try EvaluationSuiteManifest.decode(Data(repeated.utf8))

    #expect(suite.items.count == 3)
    #expect(suite.items[2].speakerID == "speaker-17")
    #expect(suite.items[2].slices == ["accent": "Scottish English"])
}

@Test func evaluationSuiteV2AcceptsTextifyLongDurationBuckets() throws {
    let suite = try EvaluationSuiteManifest.decode(Data(longDurationManifest.utf8))

    #expect(suite.compatibleItems(maxAudioSeconds: 40).map(\.id) == ["long-a"])
    #expect(suite.compatibleItems(maxAudioSeconds: 60).map(\.id) == ["long-a", "long-b"])
}

private let itemB = """
    ,
        {
          "id": "sample-b",
          "subsetID": "librispeech-clean",
          "row": 11,
          "audio": "sample-b.flac",
          "reference": "a longer reference",
          "durationMs": 28575,
          "durationBucket": "20-29",
          "sizeBytes": 1200,
          "sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        }
"""

private let repeatedItem = """
    ,
        {
          "id": "sample-c",
          "subsetID": "librispeech-clean",
          "row": 12,
          "audio": "sample-c.flac",
          "reference": "another short reference",
          "durationMs": 2500,
          "durationBucket": "1-3",
          "sizeBytes": 1100,
          "sha256": "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
          "speakerID": "speaker-17",
          "slices": { "accent": "Scottish English" }
        }
"""

private let validManifest = """
    {
      "schemaVersion": 1,
      "id": "english-pr-v1",
      "name": "English pull request evaluation",
      "language": "en",
      "dataset": {
        "id": "hf-audio/open-asr-leaderboard",
        "revision": "b6bdcd0beb34f8975dc659796176d88f43aff502",
        "viewerBaseURL": "https://datasets-server.huggingface.co"
      },
      "durationLanes": [
        { "id": "universal", "maxAudioSeconds": 29 },
        { "id": "extended-40", "maxAudioSeconds": 40 },
        { "id": "full-60", "maxAudioSeconds": 60 }
      ],
      "requiredDurationBuckets": ["1-3", "20-29"],
      "subsets": [
        {
          "id": "librispeech-clean",
          "config": "librispeech",
          "split": "test.clean",
          "role": "public-quality",
          "speechOrigin": "human-read",
          "license": "CC-BY-4.0",
          "sourceURL": "https://www.openslr.org/12"
        }
      ],
      "items": [
        {
          "id": "sample-a",
          "subsetID": "librispeech-clean",
          "row": 2229,
          "audio": "sample-a.flac",
          "reference": "a short reference",
          "durationMs": 2995,
          "durationBucket": "1-3",
          "sizeBytes": 1000,
          "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        }
        \(itemB)
      ]
    }
"""

private let noSpeechManifest = validManifest
    .replacingOccurrences(of: "\"role\": \"public-quality\"", with: "\"role\": \"negative-control\"")
    .replacingOccurrences(of: "\"speechOrigin\": \"human-read\"", with: "\"speechOrigin\": \"no-speech\"")
    .replacingOccurrences(of: "\"reference\": \"a short reference\"", with: "\"reference\": \"\"")
    .replacingOccurrences(of: "\"reference\": \"a longer reference\"", with: "\"reference\": \"\"")

private let longDurationManifest = """
    {
      "schemaVersion": 2,
      "id": "english-nightly-long-v1",
      "name": "English nightly long-duration fixture",
      "language": "en",
      "dataset": {
        "id": "example/long-duration",
        "revision": "dddddddddddddddddddddddddddddddddddddddd",
        "viewerBaseURL": "https://datasets-server.huggingface.co"
      },
      "durationLanes": [
        { "id": "extended-40", "maxAudioSeconds": 40 },
        { "id": "full-60", "maxAudioSeconds": 60 }
      ],
      "requiredDurationBuckets": ["29-45", "45-60"],
      "subsets": [
        {
          "id": "long-speech",
          "config": "default",
          "split": "test",
          "role": "product-diagnostic",
          "speechOrigin": "human-natural",
          "license": "MIT",
          "sourceURL": "https://example.com/long-duration"
        }
      ],
      "items": [
        {
          "id": "long-a",
          "subsetID": "long-speech",
          "row": 0,
          "audio": "long-a.wav",
          "reference": "a recording longer than twenty nine seconds",
          "durationMs": 35000,
          "durationBucket": "29-45",
          "sizeBytes": 1000,
          "sha256": "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"
        },
        {
          "id": "long-b",
          "subsetID": "long-speech",
          "row": 1,
          "audio": "long-b.wav",
          "reference": "a recording that exercises the full duration lane",
          "durationMs": 55000,
          "durationBucket": "45-60",
          "sizeBytes": 1000,
          "sha256": "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"
        }
      ]
    }
"""
