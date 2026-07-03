@MainActor
public final class GlobalHotkeyMonitor {
    private let permissionClient: InputMonitoringPermissionClient
    private let eventTapClient: any CGEventTapClient
    private let trigger: TriggerPreference
    private var mapper: TriggerEventMapper
    private var handle: CGEventTapHandle?
    private var sessionGeneration = 0

    public init(
        permissionClient: InputMonitoringPermissionClient = .live,
        eventTapClient: any CGEventTapClient = SystemCGEventTapClient(),
        trigger: TriggerPreference = .defaultTrigger
    ) {
        self.permissionClient = permissionClient
        self.eventTapClient = eventTapClient
        self.trigger = trigger
        self.mapper = TriggerEventMapper(trigger: trigger)
    }

    deinit {
        if let handle {
            eventTapClient.stop(handle)
        }
    }

    public func start(
        onEvent: @escaping @Sendable (TriggerEvent) -> Void,
        onFailure: @escaping @Sendable (HotkeyMonitorError) -> Void
    ) {
        guard handle == nil else {
            onFailure(.alreadyRunning)
            return
        }
        switch permissionClient.status() {
        case .granted:
            break
        case .unknown:
            onFailure(.inputMonitoringPermissionRequired)
            return
        case .denied:
            onFailure(.inputMonitoringDenied)
            return
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
        } catch let error as HotkeyMonitorError {
            onFailure(error)
        } catch {
            onFailure(.eventTapCreationFailed)
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
