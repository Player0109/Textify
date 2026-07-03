import Foundation

public protocol DownloadTransport {
    func fetch(_ request: URLRequest) async throws -> DownloadResponse
    func downloadFile(_ request: URLRequest, to temporaryURL: URL) async throws -> DownloadFileResponse
}

public struct DownloadResponse: Equatable, Sendable {
    public let data: Data
    public let eTag: String?
    public let lastModified: String?
    public let statusCode: Int?

    public init(
        data: Data,
        eTag: String? = nil,
        lastModified: String? = nil,
        statusCode: Int? = nil
    ) {
        self.data = data
        self.eTag = eTag
        self.lastModified = lastModified
        self.statusCode = statusCode
    }
}

public struct DownloadFileResponse: Equatable, Sendable {
    public let fileURL: URL
    public let eTag: String?
    public let lastModified: String?
    public let statusCode: Int?

    public init(fileURL: URL, eTag: String? = nil, lastModified: String? = nil, statusCode: Int? = nil) {
        self.fileURL = fileURL
        self.eTag = eTag
        self.lastModified = lastModified
        self.statusCode = statusCode
    }
}

public enum DownloadTransportError: Error, Equatable {
    case unacceptableStatusCode(Int)
}

public final class URLSessionDownloadTransport: DownloadTransport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetch(_ request: URLRequest) async throws -> DownloadResponse {
        let (data, response) = try await session.data(for: request)
        let httpResponse = response as? HTTPURLResponse

        if let statusCode = httpResponse?.statusCode,
           !(200..<300).contains(statusCode) {
            throw DownloadTransportError.unacceptableStatusCode(statusCode)
        }

        return DownloadResponse(
            data: data,
            eTag: httpResponse?.value(forHTTPHeaderField: "ETag"),
            lastModified: httpResponse?.value(forHTTPHeaderField: "Last-Modified"),
            statusCode: httpResponse?.statusCode
        )
    }

    public func downloadFile(_ request: URLRequest, to temporaryURL: URL) async throws -> DownloadFileResponse {
        let (downloadedURL, response) = try await session.download(for: request)
        let httpResponse = response as? HTTPURLResponse

        if let statusCode = httpResponse?.statusCode,
           !(200..<300).contains(statusCode) {
            throw DownloadTransportError.unacceptableStatusCode(statusCode)
        }

        try? FileManager.default.removeItem(at: temporaryURL)
        try FileManager.default.moveItem(at: downloadedURL, to: temporaryURL)

        return DownloadFileResponse(
            fileURL: temporaryURL,
            eTag: httpResponse?.value(forHTTPHeaderField: "ETag"),
            lastModified: httpResponse?.value(forHTTPHeaderField: "Last-Modified"),
            statusCode: httpResponse?.statusCode
        )
    }
}

public struct ModelDownloader {
    private let transport: any DownloadTransport
    private let manifestVerifier: ManifestVerifier

    public init(
        transport: any DownloadTransport = URLSessionDownloadTransport(),
        manifestVerifier: ManifestVerifier
    ) {
        self.transport = transport
        self.manifestVerifier = manifestVerifier
    }

    public static func requiredFreeBytes(modelSizeBytes: Int64) -> Int64 {
        let normalizedModelSize = max(0, modelSizeBytes)
        let requiredHeadroom = max(500_000_000, normalizedModelSize / 5)
        let addition = normalizedModelSize.addingReportingOverflow(requiredHeadroom)
        return addition.overflow ? Int64.max : addition.partialValue
    }

    public func downloadManifest(
        manifestURL: URL,
        signatureURL: URL
    ) async throws -> ModelManifest {
        let manifestResponse = try await transport.fetch(URLRequest(url: manifestURL))
        let signatureResponse = try await transport.fetch(URLRequest(url: signatureURL))

        let manifest = try manifestVerifier.verify(
            manifestData: manifestResponse.data,
            signatureData: signatureResponse.data
        )
        try ProductionModelPolicy.validateV1_1ProductionManifest(manifest)
        return manifest
    }
}
