public struct TriggerTestSessionResult: Equatable, Sendable {
    public let sawDown: Bool
    public let sawBeginRecording: Bool
    public let sawUp: Bool
    public let wasCancelled: Bool
    public let passed: Bool

    public init(
        sawDown: Bool,
        sawBeginRecording: Bool,
        sawUp: Bool,
        wasCancelled: Bool = false
    ) {
        self.sawDown = sawDown
        self.sawBeginRecording = sawBeginRecording
        self.sawUp = sawUp
        self.wasCancelled = wasCancelled
        self.passed = sawDown && sawBeginRecording && sawUp && !wasCancelled
    }

    fileprivate init(
        sawDown: Bool,
        sawBeginRecording: Bool,
        sawUp: Bool,
        wasCancelled: Bool,
        passed: Bool
    ) {
        self.sawDown = sawDown
        self.sawBeginRecording = sawBeginRecording
        self.sawUp = sawUp
        self.wasCancelled = wasCancelled
        self.passed = passed
    }
}

public actor TriggerTestSession {
    private var stateMachine: TriggerStateMachine
    private var sawDown = false
    private var sawBeginRecording = false
    private var sawUp = false
    private var wasCancelled = false
    private var holdIsActive = false
    private var activeHoldWasActivated = false
    private var sawMatchingRelease = false

    public init(activationDelayMs: Int = 250) {
        self.stateMachine = TriggerStateMachine(activationDelayMs: activationDelayMs)
    }

    public func ingest(_ event: TriggerEvent) -> TriggerTestSessionResult {
        let action = stateMachine.handle(event)
        if case .triggerDown = event {
            sawDown = true
            if case .beginArmedCapture = action {
                holdIsActive = true
                activeHoldWasActivated = false
            }
        }
        if action == .activateRecording || action == .finishRecording {
            sawBeginRecording = true
            if holdIsActive {
                activeHoldWasActivated = true
            }
        }
        if case .triggerUp = event {
            sawUp = true
            if holdIsActive, activeHoldWasActivated {
                sawMatchingRelease = true
            }
            holdIsActive = false
            activeHoldWasActivated = false
        }
        if case .escapeKeyDown = event { wasCancelled = true }
        if action == .cancelRecording { wasCancelled = true }
        return TriggerTestSessionResult(
            sawDown: sawDown,
            sawBeginRecording: sawBeginRecording,
            sawUp: sawUp,
            wasCancelled: wasCancelled,
            passed: sawDown
                && sawBeginRecording
                && sawUp
                && sawMatchingRelease
                && !wasCancelled
        )
    }
}
