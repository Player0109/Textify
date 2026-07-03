public enum ProductionModelPolicyError: Error, Equatable {
    case unsupportedManifestVersion(Int)
    case expectedSingleModel(count: Int)
    case wrongModelID(String)
    case expectedSingleFile(count: Int)
    case missingChecksum
    case invalidSize
    case languageNotEnglish
}

public enum ProductionModelPolicy {
    public static let requiredModelID = "ggml-small.en-q5_1"

    public static func validateV1_1ProductionManifest(_ manifest: ModelManifest) throws {
        guard manifest.manifestVersion == 1 else {
            throw ProductionModelPolicyError.unsupportedManifestVersion(manifest.manifestVersion)
        }
        guard manifest.models.count == 1 else {
            throw ProductionModelPolicyError.expectedSingleModel(count: manifest.models.count)
        }
        let model = manifest.models[0]
        guard model.id == requiredModelID else {
            throw ProductionModelPolicyError.wrongModelID(model.id)
        }
        guard model.files.count == 1 else {
            throw ProductionModelPolicyError.expectedSingleFile(count: model.files.count)
        }
        let file = model.files[0]
        guard !file.sha256.isEmpty else {
            throw ProductionModelPolicyError.missingChecksum
        }
        guard file.sizeBytes > 0 else {
            throw ProductionModelPolicyError.invalidSize
        }
        guard model.runtimeParameters.language == "en" else {
            throw ProductionModelPolicyError.languageNotEnglish
        }
    }
}
