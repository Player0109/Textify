public struct TriggerTestSessionResult: Equatable, Sendable {
    public let sawDown: Bool
    public let sawBeginRecording: Bool
    public let sawUp: Bool
    public let wasCancelled: Bool
    public var passed: Bool { sawDown && sawBeginRecording && sawUp && !wasCancelled }

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
    }
}

public actor TriggerTestSession {
    private var stateMachine: TriggerStateMachine
    private var sawDown = false
    private var sawBeginRecording = false
    private var sawUp = false
    private var wasCancelled = false

    public init(activationDelayMs: Int = 250) {
        self.stateMachine = TriggerStateMachine(activationDelayMs: activationDelayMs)
    }

    public func ingest(_ event: TriggerEvent) -> TriggerTestSessionResult {
        if case .triggerDown = event { sawDown = true }
        if case .triggerUp = event { sawUp = true }
        let action = stateMachine.handle(event)
        if action == .beginRecording { sawBeginRecording = true }
        if case .escapeKeyDown = event { wasCancelled = true }
        if action == .cancelRecording { wasCancelled = true }
        return TriggerTestSessionResult(
            sawDown: sawDown,
            sawBeginRecording: sawBeginRecording,
            sawUp: sawUp,
            wasCancelled: wasCancelled
        )
    }
}
