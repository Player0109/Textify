public protocol EventPoster: Sendable {
    func postPasteCommand() async throws
    func postUnicodeText(_ text: String) async throws
}
