import Foundation
import CryptoKit
import TextifyModels
import XCTest

final class DownloadTests: XCTestCase {
    func testModelFilePolicyAcceptsCommitPinnedHuggingFaceFile() throws {
        let url = try XCTUnwrap(URL(string:
            "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml/resolve/aed02740059203c4a87495924f685de3722ae9ce/Encoder.mlmodelc/weights/weight.bin"
        ))

        XCTAssertNoThrow(try ModelDownloadURLPolicy.requireApprovedModelFile(url))
    }

    func testModelFilePolicyRejectsMutableHuggingFaceRevision() throws {
        let url = try XCTUnwrap(URL(string:
            "https://huggingface.co/FluidInference/parakeet-tdt-0.6b-v3-coreml/resolve/main/Encoder.mlmodelc/weights/weight.bin"
        ))

        XCTAssertThrowsError(try ModelDownloadURLPolicy.requireApprovedModelFile(url)) { error in
            XCTAssertEqual(
                error as? ModelDownloadPolicyError,
                .unsupportedModelFileURL(url.absoluteString)
            )
        }
    }

    func testModelFilePolicyRejectsPinnedHuggingFaceURLWithQueryOrFragment() throws {
        let revision = "aed02740059203c4a87495924f685de3722ae9ce"
        let values = [
            "https://huggingface.co/FluidInference/model/resolve/\(revision)/model.bin?download=true",
            "https://huggingface.co/FluidInference/model/resolve/\(revision)/model.bin#fragment"
        ]

        for value in values {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertThrowsError(try ModelDownloadURLPolicy.requireApprovedModelFile(url))
        }
    }

    func testModelFilePolicyRejectsMalformedHuggingFaceCommitAndPath() throws {
        let revision = "AED02740059203C4A87495924F685DE3722AE9CE"
        let values = [
            "https://huggingface.co/FluidInference/model/resolve/\(revision)/model.bin",
            "https://huggingface.co/FluidInference/model/resolve/aed02740059203c4a87495924f685de3722ae9ce/folder%2Fmodel.bin",
            "https://huggingface.co/FluidInference/model/resolve/aed02740059203c4a87495924f685de3722ae9ce/../model.bin"
        ]

        for value in values {
            let url = try XCTUnwrap(URL(string: value))
            XCTAssertThrowsError(try ModelDownloadURLPolicy.requireApprovedModelFile(url))
        }
    }

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
        let downloader = ModelDownloader(
            transport: transport,
            manifestVerifier: try Self.fixtureManifestVerifier()
        )

        let manifest = try await downloader.downloadManifest(
            manifestURL: URL(string: "https://example.com/manifest.json")!,
            signatureURL: URL(string: "https://example.com/manifest.json.sig")!
        )

        XCTAssertEqual(manifest.manifestVersion, 1)
        XCTAssertEqual(manifest.models.first?.id, ProductionModelPolicy.requiredModelID)
        XCTAssertEqual(transport.requestedURLs, [
            URL(string: "https://example.com/manifest.json")!,
            URL(string: "https://example.com/manifest.json.sig")!
        ])
    }

    func testManifestSnapshotRetainsTheExactVerifiedManifestAndSignatureBytes() async throws {
        let manifestData = try Self.fixtureData("manifest.json")
        let signatureData = try Self.fixtureData("manifest.json.sig")
        let transport = FixtureDownloadTransport(responses: [
            URL(string: "https://example.com/manifest.json")!: DownloadResponse(
                data: manifestData
            ),
            URL(string: "https://example.com/manifest.json.sig")!: DownloadResponse(
                data: signatureData
            ),
        ])
        let downloader = ModelDownloader(
            transport: transport,
            manifestVerifier: try Self.fixtureManifestVerifier()
        )

        let snapshot = try await downloader.downloadManifestSnapshot(
            manifestURL: URL(string: "https://example.com/manifest.json")!,
            signatureURL: URL(string: "https://example.com/manifest.json.sig")!
        )

        XCTAssertEqual(snapshot.manifestData, manifestData)
        XCTAssertEqual(snapshot.signatureData, signatureData)
        XCTAssertEqual(snapshot.revision, snapshot.manifest.generatedAt)
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
        let downloader = ModelDownloader(
            transport: transport,
            manifestVerifier: try Self.fixtureManifestVerifier()
        )

        do {
            _ = try await downloader.downloadManifest(
                manifestURL: URL(string: "https://example.com/manifest.json")!,
                signatureURL: URL(string: "https://example.com/manifest.json.sig")!
            )
            XCTFail("Expected manifest verification to reject tampered bytes")
        } catch let error as ManifestVerificationError {
            XCTAssertEqual(error, .contentHashMismatch)
        }
    }

    func testManifestDownloadRejectsNonHTTPSManifestURLBeforeTransport() async throws {
        let transport = FixtureDownloadTransport(responses: [:])
        let downloader = ModelDownloader(
            transport: transport,
            manifestVerifier: try Self.fixtureManifestVerifier()
        )
        let manifestURL = URL(string: "http://player0109.github.io/Textify/models/manifest.json")!

        do {
            _ = try await downloader.downloadManifest(
                manifestURL: manifestURL,
                signatureURL: URL(string: "https://player0109.github.io/Textify/models/manifest.json.sig")!
            )
            XCTFail("Expected non-HTTPS manifest URL rejection")
        } catch let error as ModelDownloadPolicyError {
            XCTAssertEqual(error, .nonHTTPSURL(manifestURL.absoluteString))
        }
        XCTAssertEqual(transport.requestedURLs, [])
    }

    func testManifestDownloadRejectsNonHTTPSSignatureURLBeforeTransport() async throws {
        let transport = FixtureDownloadTransport(responses: [:])
        let downloader = ModelDownloader(
            transport: transport,
            manifestVerifier: try Self.fixtureManifestVerifier()
        )
        let signatureURL = URL(string: "http://player0109.github.io/Textify/models/manifest.json.sig")!

        do {
            _ = try await downloader.downloadManifest(
                manifestURL: URL(string: "https://player0109.github.io/Textify/models/manifest.json")!,
                signatureURL: signatureURL
            )
            XCTFail("Expected non-HTTPS signature URL rejection")
        } catch let error as ModelDownloadPolicyError {
            XCTAssertEqual(error, .nonHTTPSURL(signatureURL.absoluteString))
        }
        XCTAssertEqual(transport.requestedURLs, [])
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

    func testURLSessionDownloadTransportReportsStreamingProgress() async throws {
        let chunks = [
            Data(repeating: 0x1, count: 1_048_576),
            Data(repeating: 0x2, count: 1_048_576),
            Data(repeating: 0x3, count: 1_048_576)
        ]
        let expectedData = chunks.reduce(into: Data()) { result, chunk in
            result.append(chunk)
        }
        StreamingURLProtocol.configure(
            chunks: chunks,
            headers: ["Content-Length": "\(expectedData.count)"],
            delayNanoseconds: 20_000_000
        )
        defer { StreamingURLProtocol.reset() }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StreamingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextifyTransportProgress-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        let progressRecorder = DownloadProgressRecorder()
        let response = try await URLSessionDownloadTransport(session: session).downloadFile(
            URLRequest(url: URL(string: "https://example.com/model.bin")!),
            to: temporaryURL
        ) { progress in
            progressRecorder.append(progress)
        }

        XCTAssertEqual(try Data(contentsOf: response.fileURL), expectedData)
        let events = progressRecorder.events()
        XCTAssertTrue(
            events.contains { $0.bytesDownloaded > 0 && $0.bytesDownloaded < Int64(expectedData.count) },
            "Expected at least one partial progress event, got \(events)"
        )
        XCTAssertEqual(events.last, DownloadFileProgress(
            bytesDownloaded: Int64(expectedData.count),
            totalBytes: Int64(expectedData.count)
        ))
    }

    func testURLSessionDownloadCancellationStopsTransferAndDeletesPartialFile() async throws {
        let chunks = Array(repeating: Data(repeating: 0x7, count: 64 * 1_024), count: 20)
        let stopRecorder = StopLoadingRecorder()
        StreamingURLProtocol.configure(
            chunks: chunks,
            headers: ["Content-Length": "\(chunks.reduce(0) { $0 + $1.count })"],
            delayNanoseconds: 20_000_000,
            onStop: { stopRecorder.recordStop() }
        )
        defer { StreamingURLProtocol.reset() }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StreamingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextifyTransportCancel-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        let progressRecorder = DownloadProgressRecorder()

        let download = Task {
            try await URLSessionDownloadTransport(session: session).downloadFile(
                URLRequest(url: URL(string: "https://example.com/model.bin")!),
                to: temporaryURL
            ) { progress in
                progressRecorder.append(progress)
            }
        }

        for _ in 0..<100 where progressRecorder.events().isEmpty {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertFalse(progressRecorder.events().isEmpty)
        download.cancel()

        do {
            _ = try await download.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }

        let progressCountAfterCancellation = progressRecorder.events().count
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(stopRecorder.wasStopped())
        XCTAssertEqual(progressRecorder.events().count, progressCountAfterCancellation)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryURL.path))
    }

    func testURLSessionDownloadRejectsStreamBeyondSignedSizeAndDeletesPartialFile() async throws {
        let chunks = [
            Data(repeating: 0x1, count: 80),
            Data(repeating: 0x2, count: 80)
        ]
        let stopRecorder = StopLoadingRecorder()
        StreamingURLProtocol.configure(
            chunks: chunks,
            headers: [:],
            delayNanoseconds: 5_000_000,
            onStop: { stopRecorder.recordStop() }
        )
        defer { StreamingURLProtocol.reset() }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StreamingURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextifyTransportOversize-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }

        do {
            _ = try await URLSessionDownloadTransport(session: session).downloadFile(
                URLRequest(url: URL(string: "https://example.com/model.bin")!),
                to: temporaryURL,
                maximumBytes: 100
            ) { _ in }
            XCTFail("Expected signed-size ceiling rejection")
        } catch let error as DownloadTransportError {
            XCTAssertEqual(error, .responseTooLarge(maximumBytes: 100, receivedBytes: 160))
        }

        XCTAssertTrue(stopRecorder.wasStopped())
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryURL.path))
    }

    func testURLSessionResumableDownloadUsesValidatedRangeAndRemovesMetadata() async throws {
        let expectedData = Data("validated resumable model bytes".utf8)
        RangeURLProtocol.configure(data: expectedData, eTag: "model-v1")
        defer { RangeURLProtocol.reset() }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RangeURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TextifyResume-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let temporaryURL = directory.appendingPathComponent("model.partial")
        let metadataURL = directory.appendingPathComponent("model.partial.resume.json")
        let initialData = expectedData.prefix(10)
        try Data(initialData).write(to: temporaryURL)
        let modelURL = URL(string: "https://example.com/model.bin")!
        let checksum = SHA256Hash.hex(expectedData)
        let metadata = DownloadResumeMetadata(
            modelID: "parakeet-v3",
            url: modelURL.absoluteString,
            expectedSize: Int64(expectedData.count),
            sha256: checksum,
            eTag: "model-v1",
            lastModified: nil,
            bytesDownloaded: Int64(initialData.count)
        )
        try JSONEncoder().encode(metadata).write(to: metadataURL)

        let progressRecorder = DownloadProgressRecorder()
        let durabilityRecorder = ModelWorkflowBoundaryRecorder()
        _ = try await URLSessionDownloadTransport(
            session: session,
            durabilityObserver: durabilityRecorder.observer
        ).downloadFileResuming(
            URLRequest(url: modelURL),
            to: temporaryURL,
            metadataURL: metadataURL,
            modelID: "parakeet-v3",
            expectedSHA256: checksum,
            maximumBytes: Int64(expectedData.count),
            progress: { progressRecorder.append($0) }
        )

        XCTAssertEqual(try Data(contentsOf: temporaryURL), expectedData)
        XCTAssertEqual(RangeURLProtocol.rangeHeaders(), ["bytes=10-"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: metadataURL.path))
        XCTAssertEqual(
            durabilityRecorder.events,
            [
                ModelWorkflowBoundaryEvent(
                    boundary: .partialMetadataPersisted,
                    artifactID: "parakeet-v3"
                ),
            ]
        )
        XCTAssertEqual(
            progressRecorder.events().last,
            DownloadFileProgress(
                bytesDownloaded: Int64(expectedData.count),
                totalBytes: Int64(expectedData.count)
            )
        )
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

    private static func fixtureManifestVerifier() throws -> ManifestVerifier {
        let manifestData = try fixtureData("manifest.json")
        return ManifestVerifier(
            trustedKeys: [
                TrustedModelManifestKey(
                    keyId: "fixture-key",
                    publicKeyBase64: try fixtureString("manifest.fixture-public-key.base64")
                )
            ],
            legacyPolicy: LegacyManifestSignaturePolicy(
                keyId: "fixture-key",
                contentSHA256: SHA256Hash.hex(manifestData)
            )
        )
    }
}

private enum SHA256Hash {
    static func hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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

    func downloadFile(_ request: URLRequest, to temporaryURL: URL) async throws -> DownloadFileResponse {
        let response = try await fetch(request)
        try response.data.write(to: temporaryURL)
        return DownloadFileResponse(
            fileURL: temporaryURL,
            eTag: response.eTag,
            lastModified: response.lastModified,
            statusCode: response.statusCode
        )
    }

    func downloadFile(
        _ request: URLRequest,
        to temporaryURL: URL,
        maximumBytes: Int64,
        admissionCheck: @escaping @Sendable (
            DownloadFileProgress
        ) throws -> Void,
        progress: @escaping @Sendable (DownloadFileProgress) -> Void
    ) async throws -> DownloadFileResponse {
        let response = try await fetch(request)
        try response.data.write(to: temporaryURL)
        let event = DownloadFileProgress(
            bytesDownloaded: Int64(response.data.count),
            totalBytes: Int64(response.data.count)
        )
        try admissionCheck(event)
        progress(event)
        return DownloadFileResponse(
            fileURL: temporaryURL,
            eTag: response.eTag,
            lastModified: response.lastModified,
            statusCode: response.statusCode
        )
    }
}

private final class DownloadProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedEvents: [DownloadFileProgress] = []

    func append(_ event: DownloadFileProgress) {
        lock.lock()
        recordedEvents.append(event)
        lock.unlock()
    }

    func events() -> [DownloadFileProgress] {
        lock.lock()
        let result = recordedEvents
        lock.unlock()
        return result
    }
}

private final class StopLoadingRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false

    func recordStop() {
        lock.lock()
        stopped = true
        lock.unlock()
    }

    func wasStopped() -> Bool {
        lock.lock()
        let result = stopped
        lock.unlock()
        return result
    }
}

private final class StreamingURLProtocol: URLProtocol {
    private struct Configuration {
        let chunks: [Data]
        let headers: [String: String]
        let delayNanoseconds: UInt64
        let onStop: @Sendable () -> Void
    }

    private static let lock = NSLock()
    private static var configuration = Configuration(
        chunks: [],
        headers: [:],
        delayNanoseconds: 0,
        onStop: {}
    )

    private var loadingTask: Task<Void, Never>?

    static func configure(
        chunks: [Data],
        headers: [String: String],
        delayNanoseconds: UInt64,
        onStop: @escaping @Sendable () -> Void = {}
    ) {
        lock.lock()
        configuration = Configuration(
            chunks: chunks,
            headers: headers,
            delayNanoseconds: delayNanoseconds,
            onStop: onStop
        )
        lock.unlock()
    }

    static func reset() {
        configure(chunks: [], headers: [:], delayNanoseconds: 0)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let configuration = Self.currentConfiguration()
        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: configuration.headers
              )
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        loadingTask = Task { [weak self] in
            guard let self else {
                return
            }

            for chunk in configuration.chunks {
                if configuration.delayNanoseconds > 0 {
                    do {
                        try await Task.sleep(nanoseconds: configuration.delayNanoseconds)
                    } catch {
                        return
                    }
                }
                guard !Task.isCancelled else {
                    return
                }
                client?.urlProtocol(self, didLoad: chunk)
            }
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {
        loadingTask?.cancel()
        Self.currentConfiguration().onStop()
    }

    private static func currentConfiguration() -> Configuration {
        lock.lock()
        let result = configuration
        lock.unlock()
        return result
    }
}

private final class RangeURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var responseData = Data()
    private static var responseETag = ""
    private static var recordedRangeHeaders: [String] = []

    static func configure(data: Data, eTag: String) {
        lock.lock()
        responseData = data
        responseETag = eTag
        recordedRangeHeaders = []
        lock.unlock()
    }

    static func reset() {
        configure(data: Data(), eTag: "")
    }

    static func rangeHeaders() -> [String] {
        lock.lock()
        let result = recordedRangeHeaders
        lock.unlock()
        return result
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let snapshot = Self.snapshot()
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        if request.httpMethod == "HEAD" {
            sendResponse(
                url: url,
                statusCode: 200,
                headers: [
                    "Content-Length": "\(snapshot.data.count)",
                    "ETag": snapshot.eTag
                ],
                data: Data()
            )
            return
        }

        if let range = request.value(forHTTPHeaderField: "Range"),
           range.hasPrefix("bytes="),
           let start = Int(range.dropFirst("bytes=".count).dropLast()),
           start >= 0,
           start < snapshot.data.count {
            Self.record(range: range)
            let suffix = Data(snapshot.data.dropFirst(start))
            sendResponse(
                url: url,
                statusCode: 206,
                headers: [
                    "Content-Length": "\(suffix.count)",
                    "Content-Range": "bytes \(start)-\(snapshot.data.count - 1)/\(snapshot.data.count)",
                    "ETag": snapshot.eTag
                ],
                data: suffix
            )
            return
        }

        sendResponse(
            url: url,
            statusCode: 200,
            headers: [
                "Content-Length": "\(snapshot.data.count)",
                "ETag": snapshot.eTag
            ],
            data: snapshot.data
        )
    }

    override func stopLoading() {}

    private func sendResponse(
        url: URL,
        statusCode: Int,
        headers: [String: String],
        data: Data
    ) {
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !data.isEmpty {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func snapshot() -> (data: Data, eTag: String) {
        lock.lock()
        let result = (responseData, responseETag)
        lock.unlock()
        return result
    }

    private static func record(range: String) {
        lock.lock()
        recordedRangeHeaders.append(range)
        lock.unlock()
    }
}
