@MainActor
public final class GlobalHotkeyMonitor {
    private let eventTapClient: any CGEventTapClient
    private var trigger: TriggerPreference
    private var mapper: TriggerEventMapper
    private var handle: CGEventTapHandle?
    private var sessionGeneration = 0

    public var configuredTrigger: TriggerPreference {
        trigger
    }

    public var isRunning: Bool {
        handle != nil
    }

    public init(
        permissionClient: InputMonitoringPermissionClient = .live,
        eventTapClient: any CGEventTapClient = SystemKeyboardEventMonitorClient(),
        trigger: TriggerPreference = .defaultTrigger
    ) {
        _ = permissionClient
        self.eventTapClient = eventTapClient
        self.trigger = trigger
        self.mapper = TriggerEventMapper(trigger: trigger)
    }

    deinit {
        if let handle {
            eventTapClient.stop(handle)
        }
    }

    @discardableResult
    public func start(
        onEvent: @escaping @Sendable (TriggerEvent) -> Void,
        onFailure: @escaping @Sendable (HotkeyMonitorError) -> Void
    ) -> Result<Void, HotkeyMonitorError> {
        guard handle == nil else {
            let error = HotkeyMonitorError.alreadyRunning
            onFailure(error)
            return .failure(error)
        }
        do {
            sessionGeneration += 1
            mapper = TriggerEventMapper(trigger: trigger)
            let callbackGeneration = sessionGeneration
            handle = try eventTapClient.start { [weak self] message in
                Task { @MainActor [weak self] in
                    self?.handle(
                        message,
                        callbackGeneration: callbackGeneration,
                        onEvent: onEvent,
                        onFailure: onFailure
                    )
                }
            }
            return .success(())
        } catch let error as HotkeyMonitorError {
            onFailure(error)
            return .failure(error)
        } catch {
            let monitorError = HotkeyMonitorError.eventTapCreationFailed
            onFailure(monitorError)
            return .failure(monitorError)
        }
    }

    public func stop() {
        guard let handle else {
            return
        }
        sessionGeneration += 1
        mapper = TriggerEventMapper(trigger: trigger)
        eventTapClient.stop(handle)
        self.handle = nil
    }

    public func updateTrigger(_ trigger: TriggerPreference) {
        stop()
        self.trigger = trigger
        mapper = TriggerEventMapper(trigger: trigger)
    }

    private func handle(
        _ message: CGEventTapMessage,
        callbackGeneration: Int,
        onEvent: @escaping @Sendable (TriggerEvent) -> Void,
        onFailure: @escaping @Sendable (HotkeyMonitorError) -> Void
    ) {
        guard callbackGeneration == sessionGeneration else {
            return
        }
        switch message {
        case .keyboardEvent(let snapshot):
            guard let event = mapper.map(snapshot) else {
                return
            }
            onEvent(event)
        case .tapDisabledByTimeout:
            guard let handle else {
                return
            }
            eventTapClient.setEnabled(handle, enabled: true)
        case .tapDisabledByUserInput:
            guard handle != nil else {
                return
            }
            stop()
            onFailure(.eventTapDisabledByUserInput)
        }
    }
}
