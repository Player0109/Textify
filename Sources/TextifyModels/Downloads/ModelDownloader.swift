import Foundation

public protocol DownloadTransport {
    func fetch(_ request: URLRequest) async throws -> DownloadResponse
    func downloadFile(_ request: URLRequest, to temporaryURL: URL) async throws -> DownloadFileResponse
    func downloadFile(
        _ request: URLRequest,
        to temporaryURL: URL,
        progress: @escaping @Sendable (DownloadFileProgress) -> Void
    ) async throws -> DownloadFileResponse
    func downloadFile(
        _ request: URLRequest,
        to temporaryURL: URL,
        maximumBytes: Int64,
        progress: @escaping @Sendable (DownloadFileProgress) -> Void
    ) async throws -> DownloadFileResponse
    func downloadFile(
        _ request: URLRequest,
        to temporaryURL: URL,
        maximumBytes: Int64,
        admissionCheck: @escaping @Sendable (
            DownloadFileProgress
        ) throws -> Void,
        progress: @escaping @Sendable (DownloadFileProgress) -> Void
    ) async throws -> DownloadFileResponse
}

public protocol ResumableDownloadTransport: DownloadTransport {
    func downloadFileResuming(
        _ request: URLRequest,
        to temporaryURL: URL,
        metadataURL: URL,
        modelID: String,
        expectedSHA256: String,
        maximumBytes: Int64,
        progress: @escaping @Sendable (DownloadFileProgress) -> Void
    ) async throws -> DownloadFileResponse
    func downloadFileResuming(
        _ request: URLRequest,
        to temporaryURL: URL,
        metadataURL: URL,
        modelID: String,
        expectedSHA256: String,
        maximumBytes: Int64,
        admissionCheck: @escaping @Sendable (
            DownloadFileProgress
        ) throws -> Void,
        progress: @escaping @Sendable (DownloadFileProgress) -> Void
    ) async throws -> DownloadFileResponse
}

public extension DownloadTransport {
    func downloadFile(
        _ request: URLRequest,
        to temporaryURL: URL,
        progress: @escaping @Sendable (DownloadFileProgress) -> Void
    ) async throws -> DownloadFileResponse {
        try await downloadFile(request, to: temporaryURL)
    }

    func downloadFile(
        _ request: URLRequest,
        to temporaryURL: URL,
        maximumBytes: Int64,
        progress: @escaping @Sendable (DownloadFileProgress) -> Void
    ) async throws -> DownloadFileResponse {
        try await downloadFile(request, to: temporaryURL, progress: progress)
    }

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
    case invalidRangeResponse(expectedStartByte: Int64)
    case responseTooLarge(maximumBytes: Int64, receivedBytes: Int64)
}

public enum ModelDownloadPolicyError: Error, Equatable {
    case nonHTTPSURL(String)
    case unsupportedModelFileURL(String)
}

public enum ModelDownloadURLPolicy {
    public static func anonymousGET(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.httpBody = nil
        request.allHTTPHeaderFields = [:]
        return request
    }

    public static func requireHTTPS(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https" else {
            throw ModelDownloadPolicyError.nonHTTPSURL(url.absoluteString)
        }
    }

    public static func requireApprovedModelFile(_ url: URL) throws {
        try requireHTTPS(url)
        guard hasNoAuthorityOrSuffixOverrides(url) else {
            throw ModelDownloadPolicyError.unsupportedModelFileURL(url.absoluteString)
        }
        guard isTextifyGitHubReleaseAsset(url) || isCommitPinnedHuggingFaceFile(url) else {
            throw ModelDownloadPolicyError.unsupportedModelFileURL(url.absoluteString)
        }
    }

    private static func hasNoAuthorityOrSuffixOverrides(_ url: URL) -> Bool {
        url.user == nil
            && url.password == nil
            && url.port == nil
            && url.query == nil
            && url.fragment == nil
    }

    private static func isTextifyGitHubReleaseAsset(_ url: URL) -> Bool {
        let expectedPrefix = ["/", "Player0109", "Textify", "releases", "download"]
        let components = url.pathComponents
        return url.host?.lowercased() == "github.com"
            && components.count == expectedPrefix.count + 2
            && Array(components.prefix(expectedPrefix.count)) == expectedPrefix
            && isSafePathComponent(components[expectedPrefix.count])
            && isSafePathComponent(components[expectedPrefix.count + 1])
    }

    private static func isCommitPinnedHuggingFaceFile(_ url: URL) -> Bool {
        guard url.host?.lowercased() == "huggingface.co",
              let urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false),
              !urlComponents.percentEncodedPath.contains("%"),
              !urlComponents.percentEncodedPath.contains("//"),
              !urlComponents.percentEncodedPath.hasSuffix("/")
        else {
            return false
        }

        let components = url.pathComponents
        guard components.count >= 6,
              components[0] == "/",
              isSafePathComponent(components[1]),
              isSafePathComponent(components[2]),
              components[3] == "resolve",
              isLowercaseCommitHash(components[4])
        else {
            return false
        }
        return components.dropFirst(5).allSatisfy(isSafePathComponent)
    }

    private static func isLowercaseCommitHash(_ value: String) -> Bool {
        value.count == 40
            && value.unicodeScalars.allSatisfy {
                CharacterSet(charactersIn: "0123456789abcdef").contains($0)
            }
    }

    private static func isSafePathComponent(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && !value.contains("..")
            && value.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics
                    .union(CharacterSet(charactersIn: "._-"))
                    .contains($0)
            }
    }
}

public final class URLSessionDownloadTransport: ResumableDownloadTransport {
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
        try await downloadFile(request, to: temporaryURL) { _ in }
    }

    public func downloadFile(
        _ request: URLRequest,
        to temporaryURL: URL,
        progress: @escaping @Sendable (DownloadFileProgress) -> Void
    ) async throws -> DownloadFileResponse {
        try await downloadFile(
            request,
            to: temporaryURL,
            maximumBytes: .max,
            progress: progress
        )
    }

    public func downloadFile(
        _ request: URLRequest,
        to temporaryURL: URL,
        maximumBytes: Int64,
        progress: @escaping @Sendable (DownloadFileProgress) -> Void
    ) async throws -> DownloadFileResponse {
        try await downloadFile(
            request,
            to: temporaryURL,
            maximumBytes: maximumBytes,
            admissionCheck: { _ in },
            progress: progress
        )
    }

    public func downloadFile(
        _ request: URLRequest,
        to temporaryURL: URL,
        maximumBytes: Int64,
        admissionCheck: @escaping @Sendable (
            DownloadFileProgress
        ) throws -> Void,
        progress: @escaping @Sendable (DownloadFileProgress) -> Void
    ) async throws -> DownloadFileResponse {
        try await streamDownload(
            request,
            to: temporaryURL,
            maximumBytes: maximumBytes,
            initialBytes: 0,
            expectedRangeStart: nil,
            preservePartialOnFailure: false,
            admissionCheck: admissionCheck,
            progress: progress
        )
    }

    public func downloadFileResuming(
        _ request: URLRequest,
        to temporaryURL: URL,
        metadataURL: URL,
        modelID: String,
        expectedSHA256: String,
        maximumBytes: Int64,
        progress: @escaping @Sendable (DownloadFileProgress) -> Void
    ) async throws -> DownloadFileResponse {
        try await downloadFileResuming(
            request,
            to: temporaryURL,
            metadataURL: metadataURL,
            modelID: modelID,
            expectedSHA256: expectedSHA256,
            maximumBytes: maximumBytes,
            admissionCheck: { _ in },
            progress: progress
        )
    }

    public func downloadFileResuming(
        _ request: URLRequest,
        to temporaryURL: URL,
        metadataURL: URL,
        modelID: String,
        expectedSHA256: String,
        maximumBytes: Int64,
        admissionCheck: @escaping @Sendable (
            DownloadFileProgress
        ) throws -> Void,
        progress: @escaping @Sendable (DownloadFileProgress) -> Void
    ) async throws -> DownloadFileResponse {
        guard let url = request.url else {
            throw URLError(.badURL)
        }
        let validators = try await remoteValidators(for: request)
        let existingSize = fileSize(at: temporaryURL)
        let metadata = try? JSONDecoder().decode(
            DownloadResumeMetadata.self,
            from: Data(contentsOf: metadataURL)
        )
        let canResume = existingSize > 0
            && existingSize < maximumBytes
            && metadata?.bytesDownloaded == existingSize
            && metadata?.canResume(
                modelID: modelID,
                url: url.absoluteString,
                expectedSize: maximumBytes,
                sha256: expectedSHA256,
                eTag: validators.eTag,
                lastModified: validators.lastModified
            ) == true

        if !canResume {
            removeDownloadState(temporaryURL: temporaryURL, metadataURL: metadataURL)
        }

        let initialBytes = canResume ? existingSize : 0
        if validators.eTag != nil || validators.lastModified != nil {
            try writeResumeMetadata(
                modelID: modelID,
                url: url.absoluteString,
                expectedSize: maximumBytes,
                sha256: expectedSHA256,
                eTag: validators.eTag,
                lastModified: validators.lastModified,
                bytesDownloaded: initialBytes,
                to: metadataURL
            )
        }

        var downloadRequest = request
        if initialBytes > 0 {
            downloadRequest.setValue("bytes=\(initialBytes)-", forHTTPHeaderField: "Range")
            downloadRequest.setValue(
                validators.eTag ?? validators.lastModified,
                forHTTPHeaderField: "If-Range"
            )
        }

        do {
            let response = try await streamDownload(
                downloadRequest,
                to: temporaryURL,
                maximumBytes: maximumBytes,
                initialBytes: initialBytes,
                expectedRangeStart: initialBytes > 0 ? initialBytes : nil,
                preservePartialOnFailure: true,
                admissionCheck: admissionCheck,
                progress: progress
            )
            try? FileManager.default.removeItem(at: metadataURL)
            return response
        } catch let error as DownloadTransportError {
            removeDownloadState(temporaryURL: temporaryURL, metadataURL: metadataURL)
            throw error
        } catch {
            let partialSize = fileSize(at: temporaryURL)
            if partialSize > 0,
               partialSize < maximumBytes,
               validators.eTag != nil || validators.lastModified != nil {
                try? writeResumeMetadata(
                    modelID: modelID,
                    url: url.absoluteString,
                    expectedSize: maximumBytes,
                    sha256: expectedSHA256,
                    eTag: validators.eTag,
                    lastModified: validators.lastModified,
                    bytesDownloaded: partialSize,
                    to: metadataURL
                )
            } else {
                removeDownloadState(temporaryURL: temporaryURL, metadataURL: metadataURL)
            }
            throw error
        }
    }

    private func streamDownload(
        _ request: URLRequest,
        to temporaryURL: URL,
        maximumBytes: Int64,
        initialBytes: Int64,
        expectedRangeStart: Int64?,
        preservePartialOnFailure: Bool,
        admissionCheck: @escaping @Sendable (
            DownloadFileProgress
        ) throws -> Void,
        progress: @escaping @Sendable (DownloadFileProgress) -> Void
    ) async throws -> DownloadFileResponse {
        if initialBytes == 0 {
            try? FileManager.default.removeItem(at: temporaryURL)
            FileManager.default.createFile(atPath: temporaryURL.path, contents: nil)
        }

        let fileHandle: FileHandle
        do {
            fileHandle = try FileHandle(forWritingTo: temporaryURL)
            if initialBytes > 0 {
                _ = try fileHandle.seekToEnd()
            }
        } catch {
            if !preservePartialOnFailure {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
            throw error
        }

        let delegate = URLSessionStreamingDownloadDelegate(
            fileHandle: fileHandle,
            maximumBytes: max(0, maximumBytes),
            initialBytes: max(0, initialBytes),
            expectedRangeStart: expectedRangeStart,
            admissionCheck: admissionCheck,
            progress: progress
        )
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        let downloadSession = URLSession(
            configuration: session.configuration,
            delegate: delegate,
            delegateQueue: delegateQueue
        )
        defer {
            downloadSession.invalidateAndCancel()
        }

        let response: URLResponse
        do {
            response = try await delegate.download(request, using: downloadSession)
            try Task.checkCancellation()
        } catch {
            if !preservePartialOnFailure {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
            throw error
        }
        let httpResponse = response as? HTTPURLResponse

        if let statusCode = httpResponse?.statusCode,
           !(200..<300).contains(statusCode) {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw DownloadTransportError.unacceptableStatusCode(statusCode)
        }

        return DownloadFileResponse(
            fileURL: temporaryURL,
            eTag: httpResponse?.value(forHTTPHeaderField: "ETag"),
            lastModified: httpResponse?.value(forHTTPHeaderField: "Last-Modified"),
            statusCode: httpResponse?.statusCode
        )
    }

    private func remoteValidators(for request: URLRequest) async throws -> (eTag: String?, lastModified: String?) {
        var headRequest = request
        headRequest.httpMethod = "HEAD"
        headRequest.httpBody = nil
        let (_, response) = try await session.data(for: headRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            return (nil, nil)
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw DownloadTransportError.unacceptableStatusCode(httpResponse.statusCode)
        }
        return (
            httpResponse.value(forHTTPHeaderField: "ETag"),
            httpResponse.value(forHTTPHeaderField: "Last-Modified")
        )
    }

    private func writeResumeMetadata(
        modelID: String,
        url: String,
        expectedSize: Int64,
        sha256: String,
        eTag: String?,
        lastModified: String?,
        bytesDownloaded: Int64,
        to metadataURL: URL
    ) throws {
        let metadata = DownloadResumeMetadata(
            modelID: modelID,
            url: url,
            expectedSize: expectedSize,
            sha256: sha256,
            eTag: eTag,
            lastModified: lastModified,
            bytesDownloaded: bytesDownloaded
        )
        try JSONEncoder().encode(metadata).write(to: metadataURL, options: [.atomic])
    }

    private func removeDownloadState(temporaryURL: URL, metadataURL: URL) {
        try? FileManager.default.removeItem(at: temporaryURL)
        try? FileManager.default.removeItem(at: metadataURL)
    }

    private func fileSize(at url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
              let fileSize = values.fileSize else {
            return 0
        }
        return Int64(fileSize)
    }
}

private final class URLSessionStreamingDownloadDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let fileHandle: FileHandle
    private let maximumBytes: Int64
    private let initialBytes: Int64
    private let expectedRangeStart: Int64?
    private let admissionCheck: @Sendable (
        DownloadFileProgress
    ) throws -> Void
    private let progress: @Sendable (DownloadFileProgress) -> Void
    private let lock = NSLock()
    private var bytesDownloaded: Int64
    private var response: URLResponse?
    private var continuation: CheckedContinuation<URLResponse, Error>?
    private var completionError: (any Error)?
    private var didComplete = false
    private var dataTask: URLSessionDataTask?

    init(
        fileHandle: FileHandle,
        maximumBytes: Int64,
        initialBytes: Int64,
        expectedRangeStart: Int64?,
        admissionCheck: @escaping @Sendable (
            DownloadFileProgress
        ) throws -> Void,
        progress: @escaping @Sendable (DownloadFileProgress) -> Void
    ) {
        self.fileHandle = fileHandle
        self.maximumBytes = maximumBytes
        self.initialBytes = initialBytes
        self.expectedRangeStart = expectedRangeStart
        self.bytesDownloaded = initialBytes
        self.admissionCheck = admissionCheck
        self.progress = progress
    }

    func download(_ request: URLRequest, using session: URLSession) async throws -> URLResponse {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let dataTask = session.dataTask(with: request)
                lock.lock()
                guard !didComplete else {
                    let error = completionError ?? CancellationError()
                    lock.unlock()
                    continuation.resume(throwing: error)
                    return
                }
                self.continuation = continuation
                self.dataTask = dataTask
                lock.unlock()

                dataTask.resume()
            }
        } onCancel: {
            cancel()
        }
    }

    private func cancel() {
        let savedContinuation: CheckedContinuation<URLResponse, Error>?
        let savedDataTask: URLSessionDataTask?

        lock.lock()
        guard !didComplete else {
            lock.unlock()
            return
        }
        didComplete = true
        savedContinuation = continuation
        continuation = nil
        savedDataTask = dataTask
        dataTask = nil
        lock.unlock()

        savedDataTask?.cancel()
        try? fileHandle.close()
        savedContinuation?.resume(throwing: CancellationError())
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        lock.lock()
        self.response = response
        if let expectedRangeStart {
            let httpResponse = response as? HTTPURLResponse
            let contentRange = httpResponse?.value(forHTTPHeaderField: "Content-Range")
            guard httpResponse?.statusCode == 206,
                  contentRange?.hasPrefix("bytes \(expectedRangeStart)-") == true else {
                completionError = DownloadTransportError.invalidRangeResponse(
                    expectedStartByte: expectedRangeStart
                )
                lock.unlock()
                completionHandler(.cancel)
                return
            }
        }
        let expectedLength = response.expectedContentLength
        let totalExpectedLength = expectedLength > 0
            ? initialBytes.addingReportingOverflow(expectedLength)
            : (partialValue: Int64(0), overflow: false)
        if totalExpectedLength.overflow || totalExpectedLength.partialValue > maximumBytes {
            completionError = DownloadTransportError.responseTooLarge(
                maximumBytes: maximumBytes,
                receivedBytes: totalExpectedLength.overflow ? .max : totalExpectedLength.partialValue
            )
            lock.unlock()
            completionHandler(.cancel)
            return
        }
        lock.unlock()

        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        guard !didComplete else {
            lock.unlock()
            return
        }
        let receivedBytes = bytesDownloaded.addingReportingOverflow(Int64(data.count))
        guard !receivedBytes.overflow, receivedBytes.partialValue <= maximumBytes else {
            completionError = DownloadTransportError.responseTooLarge(
                maximumBytes: maximumBytes,
                receivedBytes: receivedBytes.overflow ? .max : receivedBytes.partialValue
            )
            lock.unlock()
            dataTask.cancel()
            return
        }
        lock.unlock()

        do {
            try fileHandle.write(contentsOf: data)
        } catch {
            lock.lock()
            completionError = error
            lock.unlock()
            dataTask.cancel()
            return
        }

        let event: DownloadFileProgress
        lock.lock()
        guard !didComplete else {
            lock.unlock()
            return
        }
        bytesDownloaded += Int64(data.count)
        let expectedLength = response?.expectedContentLength ?? dataTask.countOfBytesExpectedToReceive
        let expectedTotalBytes = expectedLength > 0
            ? initialBytes + expectedLength
            : expectedLength
        event = DownloadFileProgress(
            bytesDownloaded: bytesDownloaded,
            totalBytes: expectedTotalBytes
        )
        lock.unlock()

        do {
            try admissionCheck(event)
        } catch {
            lock.withLock {
                completionError = error
            }
            dataTask.cancel()
            return
        }
        progress(event)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        let result: Result<URLResponse, any Error>
        let savedContinuation: CheckedContinuation<URLResponse, Error>?

        lock.lock()
        if didComplete {
            lock.unlock()
            return
        }
        didComplete = true

        if let completionError {
            result = .failure(completionError)
        } else if let error {
            result = .failure(error)
        } else if let response {
            result = .success(response)
        } else {
            result = .failure(URLError(.badServerResponse))
        }
        savedContinuation = continuation
        continuation = nil
        dataTask = nil
        lock.unlock()

        try? fileHandle.close()
        savedContinuation?.resume(with: result)
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
        try await downloadManifestSnapshot(
            manifestURL: manifestURL,
            signatureURL: signatureURL
        ).manifest
    }

    public func downloadManifestSnapshot(
        manifestURL: URL,
        signatureURL: URL
    ) async throws -> TrustedCatalogSnapshot {
        try ModelDownloadURLPolicy.requireHTTPS(manifestURL)
        try ModelDownloadURLPolicy.requireHTTPS(signatureURL)

        let manifestResponse = try await transport.fetch(
            ModelDownloadURLPolicy.anonymousGET(manifestURL)
        )
        let signatureResponse = try await transport.fetch(
            ModelDownloadURLPolicy.anonymousGET(signatureURL)
        )

        return try TrustedCatalogSnapshot(
            manifestData: manifestResponse.data,
            signatureData: signatureResponse.data,
            verifier: manifestVerifier
        )
    }
}
