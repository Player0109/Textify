import Observation
import TextifyHotkeys

@MainActor
@Observable
public final class AppDictationService {
    public private(set) var status: DictationRuntimeStatus
    public private(set) var readiness: ReadinessSnapshot

    private let dependencies: RuntimeDependencies
    private var triggerStateMachine: TriggerStateMachine

    public init(
        dependencies: RuntimeDependencies,
        triggerStateMachine: TriggerStateMachine = TriggerStateMachine()
    ) {
        self.dependencies = dependencies
        self.triggerStateMachine = triggerStateMachine
        self.status = .idle
        self.readiness = ReadinessSnapshot(
            permissions: RuntimePermissionSnapshot(
                microphone: .unknown,
                accessibility: .unknown,
                inputMonitoring: .unknown
            ),
            model: .noActiveModel
        )
    }

    @discardableResult
    public func refreshReadiness() async -> ReadinessSnapshot {
        let preferences = await dependencies.settings.loadPreferences()
        let permissions = await dependencies.permissions.permissionSnapshot()
        let activeModel = await dependencies.models.resolveActiveModel(preferences: preferences)
        let modelReadiness = await dependencies.models.readiness(for: activeModel)
        let snapshot = ReadinessSnapshot(
            permissions: permissions,
            model: modelReadiness
        )
        readiness = snapshot
        return snapshot
    }

    @discardableResult
    public func handleTriggerEvent(_ event: TriggerEvent) async -> TriggerAction {
        let action = triggerStateMachine.handle(event)
        await handleTriggerAction(action)
        return action
    }

    public func handleTriggerAction(_ action: TriggerAction) async {
        switch action {
        case .none:
            return
        case .startActivationTimer:
            status = .waitingForActivation
        case .beginRecording:
            status = .recording(speechDetected: false)
        case .cancelAsShortcut:
            status = .cancelled(.shortcutUseBeforeSpeech)
        case .cancelRecording:
            status = .cancelled(.escapeKey)
        case .discardRecording:
            status = .idle
        case .finishRecording:
            status = .processing
        }
    }

    public func cancelActiveSession(reason: DictationCancellationReason) async {
        await dependencies.audio.discardRecording()
        status = .cancelled(reason)
    }
}
