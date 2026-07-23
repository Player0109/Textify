import CryptoKit
import Foundation
import Testing
@testable import BenchmarkMetrics

@Test func evaluationSuiteIndexResolvesPinnedComponentManifest() throws {
    let directory = try temporaryIndexDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let manifestURL = directory.appendingPathComponent("component.json")
    let manifestData = Data(indexComponentManifest.utf8)
    try manifestData.write(to: manifestURL)
    let indexURL = directory.appendingPathComponent("nightly-index.json")
    let index = try EvaluationSuiteIndex.decode(
        Data(indexJSON(sha256: sha256(manifestData)).utf8)
    )

    let resolved = try EvaluationSuiteIndexResolver.resolve(index: index, indexURL: indexURL)

    #expect(resolved.count == 1)
    #expect(resolved[0].manifest.id == "component-suite")
    #expect(resolved[0].component.metricsProfile == .standard)
}

@Test func evaluationSuiteIndexRejectsChangedComponentManifest() throws {
    let directory = try temporaryIndexDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let manifestURL = directory.appendingPathComponent("component.json")
    try Data(indexComponentManifest.utf8).write(to: manifestURL)
    let indexURL = directory.appendingPathComponent("nightly-index.json")
    let index = try EvaluationSuiteIndex.decode(
        Data(indexJSON(sha256: String(repeating: "f", count: 64)).utf8)
    )

    #expect(
        throws: EvaluationSuiteIndexError.manifestChecksumMismatch("component-suite")
    ) {
        try EvaluationSuiteIndexResolver.resolve(index: index, indexURL: indexURL)
    }
}

@Test func evaluationSuiteIndexRejectsUnsafeComponentPath() {
    let unsafe = indexJSON(sha256: String(repeating: "f", count: 64))
        .replacingOccurrences(of: "component.json", with: "../component.json")

    #expect(throws: EvaluationSuiteIndexError.unsafeManifestPath("../component.json")) {
        try EvaluationSuiteIndex.decode(Data(unsafe.utf8))
    }
}

@Test func evaluationSuiteIndexChecksMetricsProfileAgainstSpeechOrigin() throws {
    let directory = try temporaryIndexDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let manifestURL = directory.appendingPathComponent("component.json")
    let manifestData = Data(indexComponentManifest.utf8)
    try manifestData.write(to: manifestURL)
    let indexURL = directory.appendingPathComponent("nightly-index.json")
    let mismatched = indexJSON(sha256: sha256(manifestData))
        .replacingOccurrences(of: "\"standard\"", with: "\"negative-control\"")
    let index = try EvaluationSuiteIndex.decode(Data(mismatched.utf8))

    #expect(throws: EvaluationSuiteIndexError.metricsProfileMismatch("component-suite")) {
        try EvaluationSuiteIndexResolver.resolve(index: index, indexURL: indexURL)
    }
}

@Test func englishCatalogRatingProfileUsesOneUniversal29SecondCaseSet() throws {
    let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let indexURL = packageRoot
        .appendingPathComponent("Corpus", isDirectory: true)
        .appendingPathComponent("english-catalog-rating-v1.index.json")
    let index = try EvaluationSuiteIndex.decode(Data(contentsOf: indexURL))
    let resolved = try EvaluationSuiteIndexResolver.resolve(index: index, indexURL: indexURL)

    #expect(index.id == "english-catalog-rating-v1")
    #expect(resolved.count == 4)
    #expect(!resolved.contains { $0.component.metricsProfile == .structured })
    #expect(resolved.allSatisfy { $0.component.maxAudioSeconds <= 29 })

    var speechItems = 0
    var noSpeechItems = 0
    for component in resolved {
        let compatible = component.manifest.compatibleItems(
            maxAudioSeconds: component.component.maxAudioSeconds
        )
        #expect(
            compatible.allSatisfy {
                $0.durationMs <= component.component.maxAudioSeconds * 1_000
            }
        )
        let noSpeechSubsetIDs = Set(
            component.manifest.subsets
                .filter { $0.speechOrigin == .noSpeech }
                .map(\.id)
        )
        noSpeechItems += compatible.filter { noSpeechSubsetIDs.contains($0.subsetID) }.count
        speechItems += compatible.filter { !noSpeechSubsetIDs.contains($0.subsetID) }.count
    }

    #expect(speechItems == 732)
    #expect(noSpeechItems == 200)
    #expect(speechItems + noSpeechItems == 932)
}

private func temporaryIndexDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("textify-evaluation-index-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private func indexJSON(sha256: String) -> String {
    """
    {
      "schemaVersion": 1,
      "id": "english-nightly-v1",
      "language": "en",
      "components": [
        {
          "id": "component-suite",
          "manifest": "component.json",
          "sha256": "\(sha256)",
          "maxAudioSeconds": 29,
          "metricsProfile": "standard"
        }
      ]
    }
    """
}

private let indexComponentManifest = """
    {
      "schemaVersion": 2,
      "id": "component-suite",
      "name": "Index component fixture",
      "language": "en",
      "dataset": {
        "id": "example/component",
        "revision": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
        "viewerBaseURL": "https://datasets-server.huggingface.co"
      },
      "durationLanes": [
        { "id": "universal", "maxAudioSeconds": 29 }
      ],
      "requiredDurationBuckets": ["1-3"],
      "subsets": [
        {
          "id": "speech",
          "config": "default",
          "split": "test",
          "role": "public-quality",
          "speechOrigin": "human-natural",
          "license": "CC-BY-4.0",
          "sourceURL": "https://example.com/component"
        }
      ],
      "items": [
        {
          "id": "speech-a",
          "subsetID": "speech",
          "row": 0,
          "audio": "speech-a.wav",
          "reference": "a short reference",
          "durationMs": 2000,
          "durationBucket": "1-3",
          "sizeBytes": 1000,
          "sha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        }
      ]
    }
"""
