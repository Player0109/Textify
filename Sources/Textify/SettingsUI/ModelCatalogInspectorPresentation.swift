import Foundation

enum ModelCatalogInspectorPresentation: Equatable {
    case checkpoint(ModelCatalogCheckpointInspectorPresentation)
    case exactArtifact(ModelCatalogExactArtifactInspectorPresentation)
}

struct ModelCatalogCheckpointInspectorPresentation: Equatable {
    let id: String
    let displayName: String
    let description: String
    let referenceArtifactID: String
    let referenceArtifactName: String
    let referenceQuality: String
    let referenceSpeed: String
    let referenceQualityEvidence: String
    let referenceSpeedEvidence: String
    let referenceCompatibility: String
    let referenceCompatibilityExplanation: String
    let defaultInstallArtifactID: String?
    let defaultInstallArtifactName: String?
    let aggregateState: String
    let languages: String
    let capabilities: String
}

struct ModelCatalogExactArtifactInspectorPresentation: Equatable {
    let id: String
    let checkpointName: String
    let displayName: String
    let description: String
    let artifactFormat: String
    let numericFormat: String
    let runtime: String
    let computeRoute: String
    let compatibility: String
    let compatibilityStatus: String
    let compatibilityExplanation: String
    let qualityEvidence: String
    let speedEvidence: String
    let transferSize: String
    let localState: String
    let provenance: String
    let license: String
    let sourceURL: URL?
    let canVerify: Bool
    let localInspectionRequest: ModelCatalogArtifactInspectionRequest?
    let verificationRequest: ModelCatalogArtifactVerificationRequest?
}
