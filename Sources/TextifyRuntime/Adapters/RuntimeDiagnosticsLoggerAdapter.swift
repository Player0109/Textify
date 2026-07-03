import TextifyDiagnostics

public actor RuntimeDiagnosticsLoggerAdapter: RuntimeDiagnosticsLogging {
    private let logger: DiagnosticsLogger

    public init(logger: DiagnosticsLogger) {
        self.logger = logger
    }

    public func log(_ event: DiagnosticEvent) async {
        try? await logger.log(event)
    }
}
