import Foundation

public actor PasteInsertionService: InsertionService {
    private let pasteboard: any PasteboardClient
    private let eventPoster: any EventPoster
    private let accessibility: AccessibilityTrustClient
    private let targetChecker: any InsertionTargetChecking
    private let restoreDelayMilliseconds: Int

    public init(
        pasteboard: any PasteboardClient,
        eventPoster: any EventPoster,
        accessibility: AccessibilityTrustClient,
        targetChecker: any InsertionTargetChecking,
        restoreDelayMilliseconds: Int = 150
    ) {
        self.pasteboard = pasteboard
        self.eventPoster = eventPoster
        self.accessibility = accessibility
        self.targetChecker = targetChecker
        self.restoreDelayMilliseconds = restoreDelayMilliseconds
    }

    public func insert(_ request: InsertionRequest) async -> InsertionOutcome {
        guard !request.text.isEmpty else {
            return .notInserted(.emptyText)
        }
        guard accessibility.status() == .trusted else {
            return .notInserted(.accessibilityNotTrusted)
        }

        let targetStatus = await targetChecker.currentTargetStatus()
        if case let .blocked(block) = targetStatus {
            return .notInserted(.blockedTarget(block))
        }
        guard await targetStillMatches(request.target) else {
            return .notInserted(.targetChanged)
        }

        let snapshot: PasteboardSnapshot
        do {
            snapshot = try await pasteboard.snapshot()
        } catch {
            return await typeIfEligible(
                request,
                cause: .pasteboardSnapshotUnavailable,
                otherwise: .pasteboardSnapshotFailed
            )
        }

        let marker = PasteboardMarker()
        let writeResult: PasteboardWriteResult
        do {
            writeResult = try await pasteboard.clearAndWritePlainText(request.text, marker: marker)
        } catch let failure as PasteboardWriteFailure {
            if let failedMutationChangeCount = failure.failedMutationChangeCount {
                await restoreAfterWriteFailure(snapshot, failedWriteChangeCount: failedMutationChangeCount)
            }
            return .notInserted(.pasteboardWriteFailed)
        } catch {
            return .notInserted(.pasteboardWriteFailed)
        }

        guard await targetStillMatches(request.target) else {
            await restoreIfTextifyStillOwnsPasteboard(
                snapshot,
                marker: marker,
                writeChangeCount: writeResult.changeCount
            )
            return .notInserted(.targetChanged)
        }

        do {
            try await eventPoster.postPasteCommand()
        } catch {
            let restored = await restoreIfTextifyStillOwnsPasteboard(
                snapshot,
                marker: marker,
                writeChangeCount: writeResult.changeCount
            )
            guard restored else {
                return .notInserted(.pasteEventFailed)
            }
            return await typeIfEligible(
                request,
                cause: .pasteEventUnavailable,
                otherwise: .pasteEventFailed
            )
        }

        await waitBeforeRestore()

        guard await textifyStillOwnsPasteboard(marker: marker, writeChangeCount: writeResult.changeCount) else {
            return .pasted(
                PasteInsertionReport(pasteboardRestored: false, pasteboardRestoreFailed: false)
            )
        }

        do {
            let restored = try await pasteboard.restore(
                snapshot,
                ifCurrentChangeCountMatches: writeResult.changeCount
            )
            return .pasted(
                PasteInsertionReport(pasteboardRestored: restored, pasteboardRestoreFailed: false)
            )
        } catch {
            return .pasted(
                PasteInsertionReport(pasteboardRestored: false, pasteboardRestoreFailed: true)
            )
        }
    }

    private func waitBeforeRestore() async {
        guard restoreDelayMilliseconds > 0 else {
            return
        }
        try? await Task.sleep(nanoseconds: UInt64(restoreDelayMilliseconds) * 1_000_000)
    }

    private func targetStillMatches(_ expectedTarget: InsertionTargetIdentity?) async -> Bool {
        guard let expectedTarget else {
            return true
        }
        return await targetChecker.currentTargetIdentity() == expectedTarget
    }

    private func restoreAfterWriteFailure(_ snapshot: PasteboardSnapshot, failedWriteChangeCount: Int) async {
        _ = try? await pasteboard.restore(
            snapshot,
            ifCurrentChangeCountMatches: failedWriteChangeCount
        )
    }

    @discardableResult
    private func restoreIfTextifyStillOwnsPasteboard(
        _ snapshot: PasteboardSnapshot,
        marker: PasteboardMarker,
        writeChangeCount: Int
    ) async -> Bool {
        guard await textifyStillOwnsPasteboard(marker: marker, writeChangeCount: writeChangeCount) else {
            return false
        }
        return (try? await pasteboard.restore(
            snapshot,
            ifCurrentChangeCountMatches: writeChangeCount
        )) == true
    }

    private func textifyStillOwnsPasteboard(marker: PasteboardMarker, writeChangeCount: Int) async -> Bool {
        guard (try? await pasteboard.containsMarker(marker)) == true else {
            return false
        }
        return await pasteboard.currentChangeCount() == writeChangeCount
    }

    private func typeIfEligible(
        _ request: InsertionRequest,
        cause: TypingFallbackCause,
        otherwise failure: InsertionFailureReason
    ) async -> InsertionOutcome {
        guard let target = request.target,
              Self.isTypingEligible(request.text) else {
            return .notInserted(failure)
        }

        let targetStatus = await targetChecker.currentTargetStatus()
        if case let .blocked(block) = targetStatus {
            return .notInserted(.blockedTarget(block))
        }
        guard await targetChecker.currentTargetIdentity() == target else {
            return .notInserted(.targetChanged)
        }

        let chunks = Self.unicodeScalarChunks(request.text, limit: 20)
        for chunk in chunks {
            guard await targetChecker.currentTargetIdentity() == target else {
                return .notInserted(.targetChanged)
            }
            do {
                try await eventPoster.postUnicodeText(chunk)
            } catch {
                return .notInserted(.typingFallbackFailed)
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return .typed(TypingFallbackReport(cause: cause, chunkCount: chunks.count))
    }

    private static func isTypingEligible(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        guard !scalars.isEmpty, scalars.count <= 500 else {
            return false
        }
        return scalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }

    private static func unicodeScalarChunks(_ text: String, limit: Int) -> [String] {
        var chunks: [String] = []
        var current = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if current.count == limit {
                chunks.append(String(current))
                current = String.UnicodeScalarView()
            }
            current.append(scalar)
        }
        if !current.isEmpty {
            chunks.append(String(current))
        }
        return chunks
    }
}
