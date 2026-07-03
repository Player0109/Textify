import Foundation

public struct DiagnosticsExporter: Sendable {
    public init() {}

    public func export(events: [DiagnosticEvent]) throws -> [String: Any] {
        let encodedEvents = try events.map(Self.jsonObject)
        let document: [String: Any] = [
            "formatVersion": 1,
            "events": encodedEvents
        ]

        guard JSONSerialization.isValidJSONObject(document) else {
            throw DiagnosticsExporterError.invalidJSONObject
        }

        return document
    }

    private static func jsonObject(for event: DiagnosticEvent) throws -> [String: Any] {
        let data = try JSONEncoder().encode(event)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DiagnosticsExporterError.invalidEventObject
        }
        return object
    }
}

public enum DiagnosticsExporterError: Error, Equatable {
    case invalidEventObject
    case invalidJSONObject
}
