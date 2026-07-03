import Foundation

public struct PasteboardMarker: Equatable, Sendable {
    public let uuid: UUID
    public static let pasteboardType = "io.github.Player0109.Textify.private-marker"

    public init(uuid: UUID = UUID()) {
        self.uuid = uuid
    }
}
