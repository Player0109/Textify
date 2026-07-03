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
            model: .noActiveModel,
            blockers: [.noActiveModel]
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
            model: modelReadiness,
            blockers: Self.blockers(permissions: permissions, model: modelReadiness)
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

    private static func blockers(
        permissions: RuntimePermissionSnapshot,
        model: RuntimeModelReadiness
    ) -> [ReadinessBlocker] {
        var blockers: [ReadinessBlocker] = []
        if permissions.microphone == .denied {
            blockers.append(.microphonePermissionDenied)
        }
        if permissions.accessibility == .denied {
            blockers.append(.accessibilityPermissionDenied)
        }
        if permissions.inputMonitoring == .denied {
            blockers.append(.inputMonitoringPermissionDenied)
        }

        switch model {
        case .ready:
            break
        case .loading(let modelID), .warming(let modelID):
            blockers.append(.activeModelNotReady(modelID: modelID))
        case .noActiveModel:
            blockers.append(.noActiveModel)
        case let .missing(modelID):
            blockers.append(.activeModelMissing(modelID: modelID))
        case let .failed(modelID, _):
            blockers.append(.transcriptionRuntimeFailed(modelID: modelID))
        }

        return blockers
    }
}
