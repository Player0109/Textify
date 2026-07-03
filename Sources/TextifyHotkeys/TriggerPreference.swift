public enum TriggerPreference: String, CaseIterable, Codable, Equatable, Sendable {
    case rightCommand
    case rightOption
    case rightControl
    case controlSpace

    public static let defaultTrigger: TriggerPreference = .rightCommand
}
