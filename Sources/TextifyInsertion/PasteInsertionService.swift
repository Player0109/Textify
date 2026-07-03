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

        let snapshot: PasteboardSnapshot
        do {
            snapshot = try await pasteboard.snapshot()
        } catch {
            return .notInserted(.pasteboardSnapshotFailed)
        }

        let marker = PasteboardMarker()
        let writeResult: PasteboardWriteResult
        do {
            writeResult = try await pasteboard.clearAndWritePlainText(request.text, marker: marker)
        } catch {
            await restoreAfterWriteFailure(snapshot)
            return .notInserted(.pasteboardWriteFailed)
        }

        do {
            try await eventPoster.postPasteCommand()
        } catch {
            await restoreIfTextifyStillOwnsPasteboard(
                snapshot,
                marker: marker,
                writeChangeCount: writeResult.changeCount
            )
            return .notInserted(.pasteEventFailed)
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

    private func restoreAfterWriteFailure(_ snapshot: PasteboardSnapshot) async {
        let currentChangeCount = await pasteboard.currentChangeCount()
        _ = try? await pasteboard.restore(
            snapshot,
            ifCurrentChangeCountMatches: currentChangeCount
        )
    }

    private func restoreIfTextifyStillOwnsPasteboard(
        _ snapshot: PasteboardSnapshot,
        marker: PasteboardMarker,
        writeChangeCount: Int
    ) async {
        guard await textifyStillOwnsPasteboard(marker: marker, writeChangeCount: writeChangeCount) else {
            return
        }
        _ = try? await pasteboard.restore(
            snapshot,
            ifCurrentChangeCountMatches: writeChangeCount
        )
    }

    private func textifyStillOwnsPasteboard(marker: PasteboardMarker, writeChangeCount: Int) async -> Bool {
        guard (try? await pasteboard.containsMarker(marker)) == true else {
            return false
        }
        return await pasteboard.currentChangeCount() == writeChangeCount
    }
}
