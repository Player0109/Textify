public enum TriggerState: Equatable, Sendable {
    case idle
    case waitingForActivation(triggerDownTimestampMs: Int)
    case recording(speechDetected: Bool)
}

public struct TriggerStateMachine: Equatable, Sendable {
    public let trigger: TriggerPreference
    public let activationDelayMs: Int
    public private(set) var state: TriggerState

    public init(
        trigger: TriggerPreference = .defaultTrigger,
        activationDelayMs: Int = 250
    ) {
        self.trigger = trigger
        self.activationDelayMs = activationDelayMs
        self.state = .idle
    }

    public mutating func handle(_ event: TriggerEvent) -> TriggerAction {
        switch state {
        case .idle:
            return handleIdle(event)
        case .waitingForActivation(let triggerDownTimestampMs):
            return handleWaitingForActivation(event, triggerDownTimestampMs: triggerDownTimestampMs)
        case .recording(let speechDetected):
            return handleRecording(event, speechDetected: speechDetected)
        }
    }

    private mutating func handleIdle(_ event: TriggerEvent) -> TriggerAction {
        switch event {
        case .triggerDown(let timestampMs):
            state = .waitingForActivation(triggerDownTimestampMs: timestampMs)
            return .startActivationTimer(delayMs: activationDelayMs)
        case .triggerUp,
             .timerFired,
             .nonTriggerKeyDown,
             .speechDetected,
             .escapeKeyDown:
            return .none
        }
    }

    private mutating func handleWaitingForActivation(
        _ event: TriggerEvent,
        triggerDownTimestampMs: Int
    ) -> TriggerAction {
        switch event {
        case .timerFired(let timestampMs):
            guard timestampMs >= triggerDownTimestampMs + activationDelayMs else {
                return .none
            }
            state = .recording(speechDetected: false)
            return .beginRecording
        case .triggerUp:
            state = .idle
            return .none
        case .nonTriggerKeyDown:
            state = .idle
            return .cancelAsShortcut
        case .escapeKeyDown:
            state = .idle
            return .cancelRecording
        case .triggerDown,
             .speechDetected:
            return .none
        }
    }

    private mutating func handleRecording(
        _ event: TriggerEvent,
        speechDetected: Bool
    ) -> TriggerAction {
        switch event {
        case .triggerUp:
            state = .idle
            return speechDetected ? .finishRecording : .discardRecording
        case .nonTriggerKeyDown(_, let isModifierOnly):
            guard !speechDetected, !isModifierOnly else {
                return .none
            }
            state = .idle
            return .cancelAsShortcut
        case .speechDetected:
            state = .recording(speechDetected: true)
            return .none
        case .escapeKeyDown:
            state = .idle
            return .cancelRecording
        case .triggerDown,
             .timerFired:
            return .none
        }
    }
}
