public enum TriggerState: Equatable, Sendable {
    case idle
    case waitingForActivation(
        triggerDownTimestampMs: Int,
        speechDetected: Bool
    )
    case recording(speechDetected: Bool)
}

public struct TriggerStateMachine: Equatable, Sendable {
    public let trigger: TriggerPreference
    public let activationDelayMs: Int
    public private(set) var state: TriggerState
    private var activeTriggerDownTimestampMs: Int?

    public init(
        trigger: TriggerPreference = .defaultTrigger,
        activationDelayMs: Int = 250
    ) {
        self.trigger = trigger
        self.activationDelayMs = activationDelayMs
        self.state = .idle
        self.activeTriggerDownTimestampMs = nil
    }

    public mutating func handle(_ event: TriggerEvent) -> TriggerAction {
        switch state {
        case .idle:
            return handleIdle(event)
        case let .waitingForActivation(
            triggerDownTimestampMs,
            speechDetected
        ):
            return handleWaitingForActivation(
                event,
                triggerDownTimestampMs: triggerDownTimestampMs,
                speechDetected: speechDetected
            )
        case .recording(let speechDetected):
            return handleRecording(event, speechDetected: speechDetected)
        }
    }

    private mutating func handleIdle(_ event: TriggerEvent) -> TriggerAction {
        switch event {
        case .triggerDown(let timestampMs):
            activeTriggerDownTimestampMs = timestampMs
            state = .waitingForActivation(
                triggerDownTimestampMs: timestampMs,
                speechDetected: false
            )
            return .beginArmedCapture(delayMs: activationDelayMs)
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
        triggerDownTimestampMs: Int,
        speechDetected: Bool
    ) -> TriggerAction {
        switch event {
        case .timerFired(let timestampMs):
            guard activationDeadlineReached(
                at: timestampMs,
                triggerDownTimestampMs: triggerDownTimestampMs
            ) else {
                return .none
            }
            state = .recording(speechDetected: speechDetected)
            return .activateRecording
        case .triggerUp(let timestampMs):
            if activationDeadlineReached(
                at: timestampMs,
                triggerDownTimestampMs: triggerDownTimestampMs
            ) {
                endHold()
                return .finishRecording
            }
            endHold()
            return .discardRecording
        case let .nonTriggerKeyDown(timestampMs, isModifierOnly):
            if activationDeadlineReached(
                at: timestampMs,
                triggerDownTimestampMs: triggerDownTimestampMs
            ) {
                if speechDetected || isModifierOnly {
                    state = .recording(speechDetected: speechDetected)
                    return .activateRecording
                }
                endHold()
                return .cancelAsShortcut
            }
            endHold()
            return .cancelAsShortcut
        case .escapeKeyDown:
            endHold()
            return .cancelRecording
        case .speechDetected(let timestampMs):
            if activationDeadlineReached(
                at: timestampMs,
                triggerDownTimestampMs: triggerDownTimestampMs
            ) {
                state = .recording(speechDetected: true)
                return .activateRecording
            }
            state = .waitingForActivation(
                triggerDownTimestampMs: triggerDownTimestampMs,
                speechDetected: true
            )
            return .none
        case .triggerDown:
            return .none
        }
    }

    private mutating func handleRecording(
        _ event: TriggerEvent,
        speechDetected: Bool
    ) -> TriggerAction {
        switch event {
        case .triggerUp(let timestampMs):
            let releasedBeforeActivation = isBeforeActivationDeadline(
                timestampMs
            )
            endHold()
            return releasedBeforeActivation
                ? .discardRecording
                : .finishRecording
        case let .nonTriggerKeyDown(timestampMs, isModifierOnly):
            if isBeforeActivationDeadline(timestampMs) {
                endHold()
                return .cancelAsShortcut
            }
            guard !speechDetected, !isModifierOnly else {
                return .none
            }
            endHold()
            return .cancelAsShortcut
        case .speechDetected:
            state = .recording(speechDetected: true)
            return .none
        case .escapeKeyDown:
            endHold()
            return .cancelRecording
        case .triggerDown,
             .timerFired:
            return .none
        }
    }

    private func activationDeadlineReached(
        at timestampMs: Int,
        triggerDownTimestampMs: Int
    ) -> Bool {
        guard timestampMs >= triggerDownTimestampMs else {
            return false
        }
        return timestampMs - triggerDownTimestampMs >= activationDelayMs
    }

    private func isBeforeActivationDeadline(_ timestampMs: Int) -> Bool {
        guard let activeTriggerDownTimestampMs else {
            return false
        }
        return !activationDeadlineReached(
            at: timestampMs,
            triggerDownTimestampMs: activeTriggerDownTimestampMs
        )
    }

    private mutating func endHold() {
        activeTriggerDownTimestampMs = nil
        state = .idle
    }
}
