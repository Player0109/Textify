public protocol EventPoster: Sendable {
    func postPasteCommand() async throws
}
