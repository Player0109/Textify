public protocol EventPoster: Sendable {
    func postPasteCommand() async throws
    func postUnicodeTextChunk(_ text: String) async throws
}
