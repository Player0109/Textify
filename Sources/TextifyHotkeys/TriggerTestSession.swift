public struct TriggerTestSessionResult: Equatable, Sendable {
    public let sawDown: Bool
    public let sawBeginRecording: Bool
    public let sawUp: Bool
    public var passed: Bool { sawDown && sawBeginRecording && sawUp }

    public init(sawDown: Bool, sawBeginRecording: Bool, sawUp: Bool) {
        self.sawDown = sawDown
        self.sawBeginRecording = sawBeginRecording
        self.sawUp = sawUp
    }
}

public actor TriggerTestSession {
    private var stateMachine = TriggerStateMachine()
    private var sawDown = false
    private var sawBeginRecording = false
    private var sawUp = false

    public init() {}

    public func ingest(_ event: TriggerEvent) -> TriggerTestSessionResult {
        if case .triggerDown = event { sawDown = true }
        if case .triggerUp = event { sawUp = true }
        let action = stateMachine.handle(event)
        if action == .beginRecording { sawBeginRecording = true }
        return TriggerTestSessionResult(
            sawDown: sawDown,
            sawBeginRecording: sawBeginRecording,
            sawUp: sawUp
        )
    }
}
