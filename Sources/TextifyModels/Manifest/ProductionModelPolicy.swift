import Foundation

public enum ProductionModelPolicyError: Error, Equatable {
    case unsupportedManifestVersion(Int)
    case expectedSingleModel(count: Int)
    case wrongModelID(String)
    case expectedSingleFile(count: Int)
    case missingChecksum
    case invalidSize
    case languageNotEnglish
    case emptyCatalog
    case duplicateModelID(String)
    case modelHasNoFiles(String)
    case duplicateFilename(modelID: String, filename: String)
    case duplicateRelativePath(modelID: String, relativePath: String)
    case missingRelativePath(modelID: String, filename: String)
    case unexpectedRelativePath(modelID: String, filename: String)
    case invalidChecksum(modelID: String, filename: String)
    case invalidModelSize(modelID: String)
    case invalidCapabilities(modelID: String)
    case incompatibleRuntime(modelID: String)
    case invalidPresentation(modelID: String)
    case unsupportedTier(modelID: String, tier: String)
    case invalidMinimumAppVersion(modelID: String, version: String)
    case invalidRuntimeParameters(modelID: String)
    case invalidModelFileURL(modelID: String, url: String)
    case invalidGeneratedAt(String)
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

    public static func validateProductionManifest(_ manifest: ModelManifest) throws {
        guard manifest.manifestVersion == 1 else {
            throw ProductionModelPolicyError.unsupportedManifestVersion(manifest.manifestVersion)
        }
        guard ISO8601DateFormatter().date(from: manifest.generatedAt) != nil else {
            throw ProductionModelPolicyError.invalidGeneratedAt(manifest.generatedAt)
        }
        guard !manifest.models.isEmpty else {
            throw ProductionModelPolicyError.emptyCatalog
        }

        var modelIDs = Set<String>()
        for model in manifest.models {
            guard modelIDs.insert(model.id).inserted else {
                throw ProductionModelPolicyError.duplicateModelID(model.id)
            }
            guard !model.files.isEmpty else {
                throw ProductionModelPolicyError.modelHasNoFiles(model.id)
            }
            guard model.sizeBytes > 0 else {
                throw ProductionModelPolicyError.invalidModelSize(modelID: model.id)
            }
            guard !model.capabilities.languages.isEmpty,
                  model.capabilities.languages.allSatisfy({ !$0.isEmpty })
            else {
                throw ProductionModelPolicyError.invalidCapabilities(modelID: model.id)
            }
            let supportedTiers = [
                "recommended", "balanced", "fast", "accurate", "specialist", "experimental"
            ]
            guard supportedTiers.contains(model.tier.lowercased()) else {
                throw ProductionModelPolicyError.unsupportedTier(
                    modelID: model.id,
                    tier: model.tier
                )
            }
            if let presentation = model.presentation {
                guard !presentation.expectedFinalization.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !presentation.accuracyTradeoff.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      !presentation.requirements.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    throw ProductionModelPolicyError.invalidPresentation(modelID: model.id)
                }
            }
            guard parsedVersion(model.minAppVersion) != nil else {
                throw ProductionModelPolicyError.invalidMinimumAppVersion(
                    modelID: model.id,
                    version: model.minAppVersion
                )
            }
            guard (1...60).contains(model.runtimeParameters.maxAudioSeconds) else {
                throw ProductionModelPolicyError.invalidRuntimeParameters(modelID: model.id)
            }
            if model.runtime.engine == .fluidAudioParaformer,
               model.runtimeParameters.maxAudioSeconds > 29 {
                throw ProductionModelPolicyError.invalidRuntimeParameters(modelID: model.id)
            }

            switch (model.runtime.engine, model.runtime.accelerator, model.runtime.artifactLayout) {
            case (.whisperCpp, .metalGPU, .singleFile),
                 (.fluidAudioParakeet, .coreMLNeuralEngine, .modelDirectory),
                 (.fluidAudioParaformer, .coreMLNeuralEngine, .modelDirectory),
                 (.sherpaOnnx, .cpu, .modelDirectory),
                 (.transcribeCpp, .metalGPU, .singleFile),
                 (.mlxAudio, .metalGPU, .modelDirectory),
                 (.liteRTLM, .metalGPU, .singleFile):
                break
            default:
                throw ProductionModelPolicyError.incompatibleRuntime(modelID: model.id)
            }

            var filenames = Set<String>()
            var relativePaths = Set<String>()
            var totalFileSize: Int64 = 0
            for file in model.files {
                guard let url = URL(string: file.url) else {
                    throw ProductionModelPolicyError.invalidModelFileURL(
                        modelID: model.id,
                        url: file.url
                    )
                }
                do {
                    try ModelDownloadURLPolicy.requireApprovedModelFile(url)
                } catch {
                    throw ProductionModelPolicyError.invalidModelFileURL(
                        modelID: model.id,
                        url: file.url
                    )
                }
                guard filenames.insert(file.filename).inserted else {
                    throw ProductionModelPolicyError.duplicateFilename(
                        modelID: model.id,
                        filename: file.filename
                    )
                }
                guard file.sizeBytes > 0 else {
                    throw ProductionModelPolicyError.invalidSize
                }
                let nextTotal = totalFileSize.addingReportingOverflow(file.sizeBytes)
                guard !nextTotal.overflow else {
                    throw ProductionModelPolicyError.invalidModelSize(modelID: model.id)
                }
                totalFileSize = nextTotal.partialValue
                guard file.sha256.count == 64,
                      file.sha256.unicodeScalars.allSatisfy({
                          CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0)
                      })
                else {
                    throw ProductionModelPolicyError.invalidChecksum(
                        modelID: model.id,
                        filename: file.filename
                    )
                }

                switch model.runtime.artifactLayout {
                case .singleFile:
                    if file.relativePath != nil {
                        throw ProductionModelPolicyError.unexpectedRelativePath(
                            modelID: model.id,
                            filename: file.filename
                        )
                    }
                case .modelDirectory:
                    guard let relativePath = file.relativePath else {
                        throw ProductionModelPolicyError.missingRelativePath(
                            modelID: model.id,
                            filename: file.filename
                        )
                    }
                    guard relativePaths.insert(relativePath).inserted else {
                        throw ProductionModelPolicyError.duplicateRelativePath(
                            modelID: model.id,
                            relativePath: relativePath
                        )
                    }
                }
            }

            guard totalFileSize == model.sizeBytes else {
                throw ProductionModelPolicyError.invalidModelSize(modelID: model.id)
            }

            if model.runtime.artifactLayout == .singleFile, model.files.count != 1 {
                throw ProductionModelPolicyError.expectedSingleFile(count: model.files.count)
            }
        }
    }

    public static func appVersion(
        _ currentVersion: String,
        satisfiesMinimum minimumVersion: String
    ) -> Bool {
        guard let current = parsedVersion(currentVersion),
              let minimum = parsedVersion(minimumVersion) else {
            return false
        }
        return current.lexicographicallyPrecedes(minimum) == false
    }

    private static func parsedVersion(_ version: String) -> [Int]? {
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3 else {
            return nil
        }
        let numbers = components.compactMap { component -> Int? in
            guard !component.isEmpty,
                  component.allSatisfy(\.isNumber) else {
                return nil
            }
            return Int(component)
        }
        return numbers.count == 3 ? numbers : nil
    }
}
