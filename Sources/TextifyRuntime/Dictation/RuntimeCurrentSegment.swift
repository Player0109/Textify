public struct RuntimeCurrentSegment: Equatable, Sendable {
    public let transcriptionArtifactID: String
    public let voiceCleaningArtifactID: String?

    public init(
        transcriptionArtifactID: String,
        voiceCleaningArtifactID: String?
    ) {
        self.transcriptionArtifactID = transcriptionArtifactID
        self.voiceCleaningArtifactID = voiceCleaningArtifactID
    }

    public func owns(artifactID: String) -> Bool {
        transcriptionArtifactID == artifactID
            || voiceCleaningArtifactID == artifactID
    }
}
