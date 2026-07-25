import CryptoKit
import Foundation
import Network
import TextifyModels

public struct DeterministicModelDownloadReport: Codable, Equatable, Sendable {
    public let redirectFollowed: Bool
    public let validRangeResumed: Bool
    public let invalidRangeRejected: Bool
    public let changedValidatorRestarted: Bool
    public let disconnectRetainedOnlyVerifiedPrefix: Bool
    public let retrySucceeded: Bool
    public let cancelRemovedPartial: Bool
    public let restartRecoveredQueue: Bool
    public let offlineQueueStayedDurable: Bool
    public let freshnessExpiryBlockedTransfer: Bool
}

public enum DeterministicModelDownloadServiceError: Error {
    case failedToStart
    case invalidResponse
}

public final class DeterministicModelDownloadService: @unchecked Sendable {
    private let payload: Data
    private let queue = DispatchQueue(label: "Textify.DeterministicModelDownloadService")
    private let lock = NSLock()
    private var listener: NWListener?
    private var servicePort: UInt16?
    private var flakyRequestCount = 0

    public init(payload: Data) {
        self.payload = payload
    }

    public func start() async throws {
        let listener = try NWListener(using: .tcp, on: .any)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }

        let port = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<UInt16, Error>) in
            let gate = ListenerContinuationGate(continuation: continuation)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    guard let rawPort = listener.port?.rawValue else {
                        gate.resume(
                            throwing: DeterministicModelDownloadServiceError.failedToStart
                        )
                        return
                    }
                    gate.resume(returning: rawPort)
                case .failed(let error):
                    gate.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
        lock.withLock {
            servicePort = port
        }
    }

    public func stop() {
        lock.withLock {
            listener?.cancel()
            listener = nil
            servicePort = nil
        }
    }

    public func exercise() async throws -> DeterministicModelDownloadReport {
        guard let baseURL = lock.withLock({ () -> URL? in
            guard let servicePort else { return nil }
            return URL(string: "http://127.0.0.1:\(servicePort)")
        }) else {
            throw DeterministicModelDownloadServiceError.failedToStart
        }

        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TextifyDownloadService-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: root) }

        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let transport = URLSessionDownloadTransport(session: session)
        let checksum = SHA256.hash(data: payload)
            .map { String(format: "%02x", $0) }
            .joined()

        let redirectURL = root.appendingPathComponent("redirect.partial")
        let redirectResponse = try await transport.downloadFile(
            URLRequest(url: baseURL.appendingPathComponent("redirect")),
            to: redirectURL
        )
        let redirectFollowed = try Data(contentsOf: redirectURL) == payload
            && redirectResponse.statusCode == 200

        let validRange = try await exerciseResume(
            path: "range",
            initialBytes: 3,
            validator: "\"v1\"",
            root: root,
            baseURL: baseURL,
            checksum: checksum,
            transport: transport
        )
        let validRangeResumed = validRange.succeeded
            && validRange.statusCode == 206

        let invalidRange = try await exerciseInvalidRange(
            root: root,
            baseURL: baseURL,
            checksum: checksum,
            transport: transport
        )

        let changed = try await exerciseResume(
            path: "changed",
            initialBytes: 3,
            validator: "\"v1\"",
            root: root,
            baseURL: baseURL,
            checksum: checksum,
            transport: transport
        )
        let changedValidatorRestarted = changed.succeeded
            && changed.statusCode == 200

        let flaky = try await exerciseDisconnectAndRetry(
            root: root,
            baseURL: baseURL,
            checksum: checksum,
            transport: transport
        )
        let cancelRemovedPartial = try await exerciseCancellation(
            root: root,
            baseURL: baseURL,
            transport: transport
        )
        let queueEvidence = try ModelDurableQueueRecoveryProbe().run(
            root: root
        )
        let freshnessExpiryBlockedTransfer =
            !ModelTransferFreshnessPolicy().isFresh(
                lastSuccessfulCheckAt: Date(timeIntervalSince1970: 0),
                now: Date(timeIntervalSince1970: 12 * 60 * 60 + 1)
            )

        return DeterministicModelDownloadReport(
            redirectFollowed: redirectFollowed,
            validRangeResumed: validRangeResumed,
            invalidRangeRejected: invalidRange,
            changedValidatorRestarted: changedValidatorRestarted,
            disconnectRetainedOnlyVerifiedPrefix: flaky.retainedVerifiedPrefix,
            retrySucceeded: flaky.retrySucceeded,
            cancelRemovedPartial: cancelRemovedPartial,
            restartRecoveredQueue: queueEvidence.restartRecoveredQueue,
            offlineQueueStayedDurable: queueEvidence.offlineQueueStayedDurable,
            freshnessExpiryBlockedTransfer: freshnessExpiryBlockedTransfer
        )
    }

    private func exerciseResume(
        path: String,
        initialBytes: Int,
        validator: String,
        root: URL,
        baseURL: URL,
        checksum: String,
        transport: URLSessionDownloadTransport
    ) async throws -> (succeeded: Bool, statusCode: Int?) {
        let partialURL = root.appendingPathComponent("\(path).partial")
        let metadataURL = partialURL.appendingPathExtension("resume.json")
        try Data(payload.prefix(initialBytes)).write(to: partialURL)
        try writeMetadata(
            modelID: path,
            url: baseURL.appendingPathComponent(path),
            checksum: checksum,
            validator: validator,
            bytesDownloaded: initialBytes,
            to: metadataURL
        )
        let response = try await transport.downloadFileResuming(
            URLRequest(url: baseURL.appendingPathComponent(path)),
            to: partialURL,
            metadataURL: metadataURL,
            modelID: path,
            expectedSHA256: checksum,
            maximumBytes: Int64(payload.count),
            progress: { _ in }
        )
        return (
            try Data(contentsOf: partialURL) == payload
                && !FileManager.default.fileExists(atPath: metadataURL.path),
            response.statusCode
        )
    }

    private func exerciseInvalidRange(
        root: URL,
        baseURL: URL,
        checksum: String,
        transport: URLSessionDownloadTransport
    ) async throws -> Bool {
        let partialURL = root.appendingPathComponent("invalid-range.partial")
        let metadataURL = partialURL.appendingPathExtension("resume.json")
        try Data(payload.prefix(3)).write(to: partialURL)
        try writeMetadata(
            modelID: "invalid-range",
            url: baseURL.appendingPathComponent("invalid-range"),
            checksum: checksum,
            validator: "\"v1\"",
            bytesDownloaded: 3,
            to: metadataURL
        )
        do {
            _ = try await transport.downloadFileResuming(
                URLRequest(
                    url: baseURL.appendingPathComponent("invalid-range")
                ),
                to: partialURL,
                metadataURL: metadataURL,
                modelID: "invalid-range",
                expectedSHA256: checksum,
                maximumBytes: Int64(payload.count),
                progress: { _ in }
            )
            return false
        } catch let error as DownloadTransportError {
            return error == .invalidRangeResponse(expectedStartByte: 3)
                && !FileManager.default.fileExists(atPath: partialURL.path)
                && !FileManager.default.fileExists(atPath: metadataURL.path)
        }
    }

    private func exerciseDisconnectAndRetry(
        root: URL,
        baseURL: URL,
        checksum: String,
        transport: URLSessionDownloadTransport
    ) async throws -> (
        retainedVerifiedPrefix: Bool,
        retrySucceeded: Bool
    ) {
        let url = baseURL.appendingPathComponent("flaky")
        let partialURL = root.appendingPathComponent("flaky.partial")
        let metadataURL = partialURL.appendingPathExtension("resume.json")
        do {
            _ = try await transport.downloadFileResuming(
                URLRequest(url: url),
                to: partialURL,
                metadataURL: metadataURL,
                modelID: "flaky",
                expectedSHA256: checksum,
                maximumBytes: Int64(payload.count),
                progress: { _ in }
            )
            return (false, false)
        } catch {
            let retained = try? Data(contentsOf: partialURL)
            let metadata = try? JSONDecoder().decode(
                DownloadResumeMetadata.self,
                from: Data(contentsOf: metadataURL)
            )
            let retainedVerifiedPrefix =
                retained?.isEmpty == false
                    && payload.starts(with: retained ?? Data())
                    && metadata?.bytesDownloaded == Int64(retained?.count ?? 0)
                    && metadata?.eTag == "\"v1\""
            let response = try await transport.downloadFileResuming(
                URLRequest(url: url),
                to: partialURL,
                metadataURL: metadataURL,
                modelID: "flaky",
                expectedSHA256: checksum,
                maximumBytes: Int64(payload.count),
                progress: { _ in }
            )
            let completedPayload = try Data(contentsOf: partialURL)
            return (
                retainedVerifiedPrefix,
                response.statusCode == 206
                    && completedPayload == payload
                    && !FileManager.default.fileExists(atPath: metadataURL.path)
            )
        }
    }

    private func exerciseCancellation(
        root: URL,
        baseURL: URL,
        transport: URLSessionDownloadTransport
    ) async throws -> Bool {
        let partialURL = root.appendingPathComponent("cancel.partial")
        let task = Task {
            try await transport.downloadFile(
                URLRequest(url: baseURL.appendingPathComponent("slow")),
                to: partialURL
            )
        }
        for _ in 0..<200 {
            if (try? partialURL.resourceValues(
                forKeys: [.fileSizeKey]
            ).fileSize) ?? 0 > 0 {
                break
            }
            try await Task.sleep(nanoseconds: 2_000_000)
        }
        task.cancel()
        do {
            _ = try await task.value
            return false
        } catch {
            return !FileManager.default.fileExists(atPath: partialURL.path)
        }
    }

    private func writeMetadata(
        modelID: String,
        url: URL,
        checksum: String,
        validator: String,
        bytesDownloaded: Int,
        to metadataURL: URL
    ) throws {
        let metadata = DownloadResumeMetadata(
            modelID: modelID,
            url: url.absoluteString,
            expectedSize: Int64(payload.count),
            sha256: checksum,
            eTag: validator,
            lastModified: nil,
            bytesDownloaded: Int64(bytesDownloaded)
        )
        try JSONEncoder().encode(metadata).write(
            to: metadataURL,
            options: [.atomic]
        )
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection, accumulated: Data())
    }

    private func receiveRequest(on connection: NWConnection, accumulated: Data) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 64 * 1_024
        ) { [weak self] content, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var request = accumulated
            if let content {
                request.append(content)
            }
            if request.range(of: Data("\r\n\r\n".utf8)) != nil {
                self.respond(to: request, on: connection)
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                self.receiveRequest(on: connection, accumulated: request)
            }
        }
    }

    private func respond(to requestData: Data, on connection: NWConnection) {
        let request = String(decoding: requestData, as: UTF8.self)
        let lines = request.components(separatedBy: "\r\n")
        let requestParts = lines.first?.split(separator: " ") ?? []
        let method = requestParts.first.map(String.init) ?? "GET"
        let path = requestParts.dropFirst().first.map(String.init) ?? "/"
        let headers = Dictionary<String, String>(
            uniqueKeysWithValues: lines.dropFirst().compactMap { line in
                guard let separator = line.firstIndex(of: ":") else {
                    return nil
                }
                return (
                    line[..<separator].lowercased(),
                    line[line.index(after: separator)...]
                        .trimmingCharacters(in: .whitespaces)
                )
            }
        )

        switch path {
        case "/redirect":
            send(
                status: "302 Found",
                headers: ["Location": "/file"],
                body: Data(),
                on: connection
            )
        case "/range":
            respondWithRange(
                method: method,
                headers: headers,
                validator: "\"v1\"",
                invalidStart: false,
                on: connection
            )
        case "/invalid-range":
            respondWithRange(
                method: method,
                headers: headers,
                validator: "\"v1\"",
                invalidStart: true,
                on: connection
            )
        case "/changed":
            send(
                status: "200 OK",
                headers: ["ETag": "\"v2\""],
                body: method == "HEAD" ? Data() : payload,
                on: connection
            )
        case "/flaky":
            if method == "HEAD" {
                send(
                    status: "200 OK",
                    headers: ["ETag": "\"v1\""],
                    body: Data(),
                    on: connection
                )
            } else if lock.withLock({
                flakyRequestCount += 1
                return flakyRequestCount
            }) == 1 {
                disconnectHalfway(on: connection)
            } else {
                respondWithRange(
                    method: method,
                    headers: headers,
                    validator: "\"v1\"",
                    invalidStart: false,
                    on: connection
                )
            }
        case "/slow":
            sendSlowResponse(on: connection)
        default:
            send(
                status: "200 OK",
                headers: ["ETag": "\"v1\""],
                body: method == "HEAD" ? Data() : payload,
                on: connection
            )
        }
    }

    private func respondWithRange(
        method: String,
        headers: [String: String],
        validator: String,
        invalidStart: Bool,
        on connection: NWConnection
    ) {
        guard method != "HEAD" else {
            send(
                status: "200 OK",
                headers: ["ETag": validator],
                body: Data(),
                on: connection
            )
            return
        }
        let requestedStart = headers["range"]
            .flatMap { $0.split(separator: "=").last }
            .flatMap { $0.split(separator: "-").first }
            .flatMap { Int($0) } ?? 0
        guard requestedStart > 0 else {
            send(
                status: "200 OK",
                headers: ["ETag": validator],
                body: payload,
                on: connection
            )
            return
        }
        let responseStart = invalidStart ? 0 : requestedStart
        let body = Data(payload.dropFirst(requestedStart))
        send(
            status: "206 Partial Content",
            headers: [
                "Content-Range":
                    "bytes \(responseStart)-\(payload.count - 1)/\(payload.count)",
                "ETag": validator,
            ],
            body: body,
            on: connection
        )
    }

    private func disconnectHalfway(on connection: NWConnection) {
        let header = Data(
            "HTTP/1.1 200 OK\r\nContent-Length: \(payload.count)\r\nETag: \"v1\"\r\nConnection: close\r\n\r\n"
                .utf8
        )
        let partial = payload.prefix(max(1, payload.count / 2))
        connection.send(
            content: header + partial,
            completion: .contentProcessed { [weak self] _ in
                self?.queue.asyncAfter(deadline: .now() + 0.05) {
                    connection.cancel()
                }
            }
        )
    }

    private func sendSlowResponse(on connection: NWConnection) {
        let header = Data(
            "HTTP/1.1 200 OK\r\nContent-Length: \(payload.count)\r\nETag: \"v1\"\r\nConnection: close\r\n\r\n"
                .utf8
        )
        let split = max(1, payload.count / 2)
        connection.send(
            content: header + payload.prefix(split),
            completion: .contentProcessed { [weak self] error in
                guard error == nil, let self else {
                    connection.cancel()
                    return
                }
                self.queue.asyncAfter(deadline: .now() + 1) {
                    connection.send(
                        content: self.payload.dropFirst(split),
                        completion: .contentProcessed {
                            _ in connection.cancel()
                        }
                    )
                }
            }
        )
    }

    private func send(
        status: String,
        headers: [String: String],
        body: Data,
        on connection: NWConnection
    ) {
        var headerLines = [
            "HTTP/1.1 \(status)",
            "Content-Length: \(body.count)",
            "Connection: close"
        ]
        headerLines.append(
            contentsOf: headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }
        )
        let header = Data((headerLines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        connection.send(
            content: header + body,
            completion: .contentProcessed { _ in connection.cancel() }
        )
    }
}

private final class ListenerContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<UInt16, Error>?

    init(continuation: CheckedContinuation<UInt16, Error>) {
        self.continuation = continuation
    }

    func resume(returning port: UInt16) {
        takeContinuation()?.resume(returning: port)
    }

    func resume(throwing error: Error) {
        takeContinuation()?.resume(throwing: error)
    }

    private func takeContinuation() -> CheckedContinuation<UInt16, Error>? {
        lock.withLock {
            defer { continuation = nil }
            return continuation
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
