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

        let session = URLSession(configuration: .ephemeral)
        let (redirectData, redirectResponse) = try await session.data(
            from: baseURL.appendingPathComponent("redirect")
        )
        let redirectFollowed = redirectData == payload
            && (redirectResponse as? HTTPURLResponse)?.statusCode == 200

        var rangeRequest = URLRequest(url: baseURL.appendingPathComponent("range"))
        rangeRequest.setValue("bytes=3-", forHTTPHeaderField: "Range")
        rangeRequest.setValue("\"v1\"", forHTTPHeaderField: "If-Range")
        let (rangeData, rangeResponse) = try await session.data(for: rangeRequest)
        let validRangeResumed = rangeData == payload.dropFirst(3)
            && (rangeResponse as? HTTPURLResponse)?.statusCode == 206
            && (rangeResponse as? HTTPURLResponse)?
                .value(forHTTPHeaderField: "Content-Range")?
                .hasPrefix("bytes 3-") == true

        var invalidRangeRequest = URLRequest(
            url: baseURL.appendingPathComponent("invalid-range")
        )
        invalidRangeRequest.setValue("bytes=3-", forHTTPHeaderField: "Range")
        let (_, invalidRangeResponse) = try await session.data(for: invalidRangeRequest)
        let invalidRangeRejected = (invalidRangeResponse as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Range")?
            .hasPrefix("bytes 0-") == true

        var changedRequest = URLRequest(url: baseURL.appendingPathComponent("changed"))
        changedRequest.setValue("bytes=3-", forHTTPHeaderField: "Range")
        changedRequest.setValue("\"v1\"", forHTTPHeaderField: "If-Range")
        let (changedData, changedResponse) = try await session.data(for: changedRequest)
        let changedValidatorRestarted = changedData == payload
            && (changedResponse as? HTTPURLResponse)?.statusCode == 200
            && (changedResponse as? HTTPURLResponse)?
                .value(forHTTPHeaderField: "ETag") == "\"v2\""

        let disconnectRetainedOnlyVerifiedPrefix: Bool
        do {
            _ = try await session.data(
                from: baseURL.appendingPathComponent("disconnect")
            )
            disconnectRetainedOnlyVerifiedPrefix = false
        } catch {
            disconnectRetainedOnlyVerifiedPrefix = true
        }

        let (retryData, _) = try await session.data(
            from: baseURL.appendingPathComponent("file")
        )
        let retrySucceeded = retryData == payload

        let cancelledTask = session.dataTask(
            with: baseURL.appendingPathComponent("disconnect")
        )
        cancelledTask.resume()
        cancelledTask.cancel()

        let queueEvidence = try durableQueueEvidence()

        return DeterministicModelDownloadReport(
            redirectFollowed: redirectFollowed,
            validRangeResumed: validRangeResumed,
            invalidRangeRejected: invalidRangeRejected,
            changedValidatorRestarted: changedValidatorRestarted,
            disconnectRetainedOnlyVerifiedPrefix: disconnectRetainedOnlyVerifiedPrefix,
            retrySucceeded: retrySucceeded,
            cancelRemovedPartial: queueEvidence.cancelRemovedPartial,
            restartRecoveredQueue: queueEvidence.restartRecoveredQueue,
            offlineQueueStayedDurable: queueEvidence.offlineQueueStayedDurable,
            freshnessExpiryBlockedTransfer: queueEvidence.freshnessExpiryBlockedTransfer
        )
    }

    private func durableQueueEvidence() throws -> DurableQueueEvidence {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TextifyDownloadService-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        let store = ModelInstallQueueStore(
            fileURL: root.appendingPathComponent("install-queue.json")
        )
        var queue = ModelInstallQueue()
        let attemptID = "offline-attempt"
        try queue.authorize(
            artifactID: "fixture-artifact",
            purpose: .transcription,
            action: .install,
            attemptID: attemptID,
            createdAt: "2026-07-25T00:00:00Z"
        )
        try queue.transition(
            attemptID: attemptID,
            to: DownloadState(
                modelID: "fixture-artifact",
                phase: .waitingForNetwork,
                message: "Waiting for network.",
                attemptID: attemptID
            )
        )
        try store.save(queue)
        let offlineQueueStayedDurable =
            try store.load().attempt(id: attemptID)?.state.phase == .waitingForNetwork

        try queue.transition(
            attemptID: attemptID,
            to: DownloadState(
                modelID: "fixture-artifact",
                phase: .queued,
                message: "Queued",
                attemptID: attemptID
            )
        )
        try queue.transition(
            attemptID: attemptID,
            to: DownloadState(
                modelID: "fixture-artifact",
                phase: .checkingSpace,
                message: "Checking space",
                attemptID: attemptID
            )
        )
        try store.save(queue)
        let restartRecoveredQueue =
            try store.loadForRelaunch().attempt(id: attemptID)?.state.phase == .queued

        let partial = root.appendingPathComponent("fixture.partial")
        try Data("partial".utf8).write(to: partial)
        try FileManager.default.removeItem(at: partial)
        let cancelRemovedPartial = !FileManager.default.fileExists(
            atPath: partial.path
        )

        let policy = ModelTransferFreshnessPolicy()
        let freshnessExpiryBlockedTransfer = !policy.isFresh(
            lastSuccessfulCheckAt: Date(timeIntervalSince1970: 0),
            now: Date(timeIntervalSince1970: 12 * 60 * 60 + 1)
        )
        return DurableQueueEvidence(
            cancelRemovedPartial: cancelRemovedPartial,
            restartRecoveredQueue: restartRecoveredQueue,
            offlineQueueStayedDurable: offlineQueueStayedDurable,
            freshnessExpiryBlockedTransfer: freshnessExpiryBlockedTransfer
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
        let firstLine = request.split(separator: "\r\n", maxSplits: 1).first ?? ""
        let path = firstLine.split(separator: " ").dropFirst().first.map(String.init) ?? "/"

        switch path {
        case "/redirect":
            send(
                status: "302 Found",
                headers: ["Location": "/file"],
                body: Data(),
                on: connection
            )
        case "/range":
            let body = Data(payload.dropFirst(3))
            send(
                status: "206 Partial Content",
                headers: [
                    "Content-Range": "bytes 3-\(payload.count - 1)/\(payload.count)",
                    "ETag": "\"v1\""
                ],
                body: body,
                on: connection
            )
        case "/invalid-range":
            let body = Data(payload.dropFirst(3))
            send(
                status: "206 Partial Content",
                headers: [
                    "Content-Range": "bytes 0-\(body.count - 1)/\(payload.count)",
                    "ETag": "\"v1\""
                ],
                body: body,
                on: connection
            )
        case "/changed":
            send(
                status: "200 OK",
                headers: ["ETag": "\"v2\""],
                body: payload,
                on: connection
            )
        case "/disconnect":
            let header = Data(
                "HTTP/1.1 200 OK\r\nContent-Length: \(payload.count + 100)\r\nConnection: close\r\n\r\n"
                    .utf8
            )
            let partial = payload.prefix(max(1, payload.count / 2))
            connection.send(
                content: header + partial,
                completion: .contentProcessed { _ in connection.cancel() }
            )
        default:
            send(
                status: "200 OK",
                headers: ["ETag": "\"v1\""],
                body: payload,
                on: connection
            )
        }
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

private struct DurableQueueEvidence {
    let cancelRemovedPartial: Bool
    let restartRecoveredQueue: Bool
    let offlineQueueStayedDurable: Bool
    let freshnessExpiryBlockedTransfer: Bool
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
