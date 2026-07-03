import Foundation
import TextifyModels
import XCTest

final class DownloadTests: XCTestCase {
    func testFreeSpaceRule() {
        XCTAssertEqual(ModelDownloader.requiredFreeBytes(modelSizeBytes: 1_000), 500_001_000)
        XCTAssertEqual(ModelDownloader.requiredFreeBytes(modelSizeBytes: 4_000_000_000), 4_800_000_000)
    }

    func testResumeRequiresMatchingValidators() {
        let metadata = DownloadResumeMetadata(
            modelID: "balanced",
            url: "https://example.com/model.bin",
            expectedSize: 10,
            sha256: "abc",
            eTag: "v1",
            lastModified: nil,
            bytesDownloaded: 5
        )

        XCTAssertTrue(metadata.canResume(
            url: "https://example.com/model.bin",
            expectedSize: 10,
            eTag: "v1",
            lastModified: nil
        ))
        XCTAssertFalse(metadata.canResume(
            url: "https://example.com/model.bin",
            expectedSize: 10,
            eTag: "v2",
            lastModified: nil
        ))
    }

    func testManifestDownloadUsesInjectedTransportAndVerifier() async throws {
        let transport = FixtureDownloadTransport(responses: [
            URL(string: "https://example.com/manifest.json")!: DownloadResponse(
                data: try Self.fixtureData("manifest.json")
            ),
            URL(string: "https://example.com/manifest.json.sig")!: DownloadResponse(
                data: try Self.fixtureData("manifest.json.sig")
            )
        ])
        let downloader = ModelDownloader(transport: transport)

        let manifest = try await downloader.downloadManifest(
            manifestURL: URL(string: "https://example.com/manifest.json")!,
            signatureURL: URL(string: "https://example.com/manifest.json.sig")!,
            publicKeyBase64: try Self.fixtureString("manifest.fixture-public-key.base64")
        )

        XCTAssertEqual(manifest.manifestVersion, 1)
        XCTAssertEqual(manifest.models.first?.id, "whisper-base-en-fast")
        XCTAssertEqual(transport.requestedURLs, [
            URL(string: "https://example.com/manifest.json")!,
            URL(string: "https://example.com/manifest.json.sig")!
        ])
    }

    func testManifestDownloadRejectsTamperedManifestBytes() async throws {
        var tamperedManifest = try Self.fixtureData("manifest.json")
        tamperedManifest.append(Data("\n".utf8))
        let transport = FixtureDownloadTransport(responses: [
            URL(string: "https://example.com/manifest.json")!: DownloadResponse(data: tamperedManifest),
            URL(string: "https://example.com/manifest.json.sig")!: DownloadResponse(
                data: try Self.fixtureData("manifest.json.sig")
            )
        ])
        let downloader = ModelDownloader(transport: transport)

        do {
            _ = try await downloader.downloadManifest(
                manifestURL: URL(string: "https://example.com/manifest.json")!,
                signatureURL: URL(string: "https://example.com/manifest.json.sig")!,
                publicKeyBase64: try Self.fixtureString("manifest.fixture-public-key.base64")
            )
            XCTFail("Expected manifest verification to reject tampered bytes")
        } catch ManifestVerificationError.contentHashMismatch {
            // Expected path from ManifestVerifier.
        }
    }

    func testDownloadStateReportsProgressFraction() {
        let state = DownloadState(
            modelID: "balanced",
            phase: .downloading,
            bytesDownloaded: 25,
            totalBytes: 100
        )

        XCTAssertEqual(state.progressFraction, 0.25)
    }

    private static func fixtureData(_ name: String) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(
                forResource: name,
                withExtension: nil,
                subdirectory: "Fixtures/Models"
            )
        )
        return try Data(contentsOf: url)
    }

    private static func fixtureString(_ name: String) throws -> String {
        String(decoding: try fixtureData(name), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private final class FixtureDownloadTransport: DownloadTransport {
    private let responses: [URL: DownloadResponse]
    private(set) var requestedURLs: [URL] = []

    init(responses: [URL: DownloadResponse]) {
        self.responses = responses
    }

    func fetch(_ request: URLRequest) async throws -> DownloadResponse {
        let url = try XCTUnwrap(request.url)
        requestedURLs.append(url)
        return try XCTUnwrap(responses[url])
    }
}
