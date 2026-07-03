public final class GlobalHotkeyMonitor: @unchecked Sendable {
    private let permissionClient: InputMonitoringPermissionClient
    private let eventTapClient: any CGEventTapClient
    private var mapper: TriggerEventMapper
    private var handle: CGEventTapHandle?

    public init(
        permissionClient: InputMonitoringPermissionClient = .live,
        eventTapClient: any CGEventTapClient = SystemCGEventTapClient(),
        trigger: TriggerPreference = .defaultTrigger
    ) {
        self.permissionClient = permissionClient
        self.eventTapClient = eventTapClient
        self.mapper = TriggerEventMapper(trigger: trigger)
    }

    public func start(
        onEvent: @escaping @Sendable (TriggerEvent) -> Void,
        onFailure: @escaping @Sendable (HotkeyMonitorError) -> Void
    ) {
        guard handle == nil else {
            onFailure(.alreadyRunning)
            return
        }
        guard permissionClient.status() != .denied else {
            onFailure(.inputMonitoringDenied)
            return
        }
        do {
            handle = try eventTapClient.start { [weak self] snapshot in
                guard let self, let event = self.mapper.map(snapshot) else {
                    return
                }
                onEvent(event)
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
        eventTapClient.stop(handle)
        self.handle = nil
    }
}
