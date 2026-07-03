public enum MicrophoneSelection: Codable, Equatable, Sendable {
    case systemDefault
    case device(deviceUID: String, lastSeenDisplayName: String)

    private enum CodingKeys: String, CodingKey {
        case type
        case deviceUID
        case lastSeenDisplayName
    }

    private enum SelectionType: String, Codable {
        case systemDefault
        case device
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(SelectionType.self, forKey: .type)

        switch type {
        case .systemDefault:
            self = .systemDefault
        case .device:
            self = .device(
                deviceUID: try container.decode(String.self, forKey: .deviceUID),
                lastSeenDisplayName: try container.decode(String.self, forKey: .lastSeenDisplayName)
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .systemDefault:
            try container.encode(SelectionType.systemDefault, forKey: .type)
        case let .device(deviceUID, lastSeenDisplayName):
            try container.encode(SelectionType.device, forKey: .type)
            try container.encode(deviceUID, forKey: .deviceUID)
            try container.encode(lastSeenDisplayName, forKey: .lastSeenDisplayName)
        }
    }
}
