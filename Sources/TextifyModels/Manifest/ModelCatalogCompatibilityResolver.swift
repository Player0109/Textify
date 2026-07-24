public enum ModelCatalogIncompatibility: Equatable, Sendable {
    case unsupportedArchitecture(
        current: ModelArchitecture?,
        supported: [ModelArchitecture]
    )
    case insufficientMemory(requiredBytes: Int64, availableBytes: Int64)
    case unsupportedRuntime(TranscriptionEngine)
    case unsupportedArtifactLayout(ModelArtifactLayout)
    case unsupportedComputeRoute(ModelComputeRoute)
}

public enum ModelCatalogCompatibilityIndeterminacy: Equatable, Sendable {
    case trustedManifestUnavailable
    case signedPresentationUnavailable(modelID: String)
    case operationalModelUnavailable(modelID: String)
    case exactArtifactUnavailable(modelID: String)
    case inconsistentSignedMetadata(modelID: String)
    case invalidCurrentAppVersion(String)
    case invalidCurrentMacOSVersion(String)
    case invalidSignedRequirements(modelID: String)
    case physicalMemoryUnavailable
}

public enum ModelCatalogCompatibility: Equatable, Sendable {
    case compatible
    case requiresAppUpdate(minimumVersion: String)
    case requiresMacOSUpdate(minimumVersion: String)
    case incompatible(ModelCatalogIncompatibility)
    case indeterminate(ModelCatalogCompatibilityIndeterminacy)

    public var allowsModelOperations: Bool {
        self == .compatible
    }
}

public struct ModelCatalogFallbackResolution: Equatable, Sendable {
    public let recommendedArtifactID: String
    public let fallbackArtifactID: String

    public init(
        recommendedArtifactID: String,
        fallbackArtifactID: String
    ) {
        self.recommendedArtifactID = recommendedArtifactID
        self.fallbackArtifactID = fallbackArtifactID
    }
}

public struct ModelCatalogCheckpointResolution: Equatable, Sendable {
    public let checkpointID: String
    public let recommendedArtifactID: String
    public let recommendedCompatibility: ModelCatalogCompatibility
    public let installArtifactID: String?
    public let fallback: ModelCatalogFallbackResolution?

    public init(
        checkpointID: String,
        recommendedArtifactID: String,
        recommendedCompatibility: ModelCatalogCompatibility,
        installArtifactID: String?,
        fallback: ModelCatalogFallbackResolution?
    ) {
        self.checkpointID = checkpointID
        self.recommendedArtifactID = recommendedArtifactID
        self.recommendedCompatibility = recommendedCompatibility
        self.installArtifactID = installArtifactID
        self.fallback = fallback
    }
}

public struct ModelCatalogCompatibilityContext: Equatable {
    public let appVersion: String
    public let macOSVersion: String
    public let architecture: ModelArchitecture?
    public let physicalMemoryBytes: Int64
    public let supportedRuntimes: [TranscriptionEngine]
    public let supportedArtifactLayouts: [ModelArtifactLayout]
    public let supportedComputeRoutes: [ModelComputeRoute]

    public init(
        appVersion: String,
        macOSVersion: String,
        architecture: ModelArchitecture?,
        physicalMemoryBytes: Int64,
        supportedRuntimes: [TranscriptionEngine] = TranscriptionEngine.allCases,
        supportedArtifactLayouts: [ModelArtifactLayout] = ModelArtifactLayout.allCases,
        supportedComputeRoutes: [ModelComputeRoute] = ModelComputeRoute.allCases
    ) {
        self.appVersion = appVersion
        self.macOSVersion = macOSVersion
        self.architecture = architecture
        self.physicalMemoryBytes = physicalMemoryBytes
        self.supportedRuntimes = supportedRuntimes
        self.supportedArtifactLayouts = supportedArtifactLayouts
        self.supportedComputeRoutes = supportedComputeRoutes
    }
}

public final class ModelCatalogCompatibilityResolver {
    public let context: ModelCatalogCompatibilityContext

    public init(context: ModelCatalogCompatibilityContext) {
        self.context = context
    }

    public func compatibility(
        for modelID: String,
        in manifest: ModelManifest?
    ) -> ModelCatalogCompatibility {
        guard let manifest else {
            return .indeterminate(.trustedManifestUnavailable)
        }
        guard let model = manifest.models.first(where: { $0.id == modelID }) else {
            return .indeterminate(.operationalModelUnavailable(modelID: modelID))
        }
        guard let graph = manifest.presentationGraph else {
            if ModelManifestSchemaVersion(rawValue: manifest.manifestVersion)?
                .requiresPresentationGraph == true {
                return .indeterminate(
                    .signedPresentationUnavailable(modelID: modelID)
                )
            }
            return legacyCompatibility(for: model)
        }
        guard let artifact = graph.artifacts.first(where: { $0.id == modelID }) else {
            return .indeterminate(.exactArtifactUnavailable(modelID: modelID))
        }
        return compatibility(for: artifact, model: model)
    }

    public func compatibilityByModelID(
        in manifest: ModelManifest?
    ) -> [String: ModelCatalogCompatibility]? {
        guard let manifest else {
            return nil
        }
        return Dictionary(
            uniqueKeysWithValues: manifest.models.map {
                ($0.id, compatibility(for: $0.id, in: manifest))
            }
        )
    }

    public func checkpointResolution(
        for checkpointID: String,
        in manifest: ModelManifest?
    ) -> ModelCatalogCheckpointResolution? {
        guard let manifest,
              let checkpoint = manifest.presentationGraph?.checkpoints.first(
                  where: { $0.id == checkpointID }
              )
        else {
            return nil
        }

        let recommendedCompatibility = compatibility(
            for: checkpoint.recommendedArtifactID,
            in: manifest
        )
        if recommendedCompatibility == .compatible {
            return ModelCatalogCheckpointResolution(
                checkpointID: checkpoint.id,
                recommendedArtifactID: checkpoint.recommendedArtifactID,
                recommendedCompatibility: recommendedCompatibility,
                installArtifactID: checkpoint.recommendedArtifactID,
                fallback: nil
            )
        }

        guard case .incompatible = recommendedCompatibility else {
            return ModelCatalogCheckpointResolution(
                checkpointID: checkpoint.id,
                recommendedArtifactID: checkpoint.recommendedArtifactID,
                recommendedCompatibility: recommendedCompatibility,
                installArtifactID: nil,
                fallback: nil
            )
        }

        for fallbackArtifactID in checkpoint.fallbackArtifactIDs
        where compatibility(for: fallbackArtifactID, in: manifest) == .compatible {
            return ModelCatalogCheckpointResolution(
                checkpointID: checkpoint.id,
                recommendedArtifactID: checkpoint.recommendedArtifactID,
                recommendedCompatibility: recommendedCompatibility,
                installArtifactID: fallbackArtifactID,
                fallback: ModelCatalogFallbackResolution(
                    recommendedArtifactID: checkpoint.recommendedArtifactID,
                    fallbackArtifactID: fallbackArtifactID
                )
            )
        }

        return ModelCatalogCheckpointResolution(
            checkpointID: checkpoint.id,
            recommendedArtifactID: checkpoint.recommendedArtifactID,
            recommendedCompatibility: recommendedCompatibility,
            installArtifactID: nil,
            fallback: nil
        )
    }

    public func checkpointResolutions(
        in manifest: ModelManifest?
    ) -> [String: ModelCatalogCheckpointResolution]? {
        guard let manifest,
              let checkpoints = manifest.presentationGraph?.checkpoints
        else {
            return nil
        }
        return Dictionary(
            uniqueKeysWithValues: checkpoints.compactMap { checkpoint in
                checkpointResolution(for: checkpoint.id, in: manifest).map {
                    (checkpoint.id, $0)
                }
            }
        )
    }

    public func compatibleModelIDs(in manifest: ModelManifest?) -> Set<String>? {
        guard let manifest else {
            return nil
        }
        return Set(manifest.models.compactMap { model in
            compatibility(for: model.id, in: manifest) == .compatible
                ? model.id
                : nil
        })
    }

    private func legacyCompatibility(
        for model: ModelEntry
    ) -> ModelCatalogCompatibility {
        guard Self.isValidVersion(context.appVersion) else {
            return .indeterminate(
                .invalidCurrentAppVersion(context.appVersion)
            )
        }
        guard Self.isValidVersion(model.minAppVersion) else {
            return .indeterminate(.invalidSignedRequirements(modelID: model.id))
        }
        guard ProductionModelPolicy.appVersion(
            context.appVersion,
            satisfiesMinimum: model.minAppVersion
        ) else {
            return .requiresAppUpdate(minimumVersion: model.minAppVersion)
        }
        return .compatible
    }

    private func compatibility(
        for artifact: ModelExactArtifactPresentationNode,
        model: ModelEntry
    ) -> ModelCatalogCompatibility {
        let requirements = artifact.compatibility
        guard Self.isValidVersion(context.appVersion) else {
            return .indeterminate(
                .invalidCurrentAppVersion(context.appVersion)
            )
        }
        guard Self.isValidVersion(context.macOSVersion) else {
            return .indeterminate(
                .invalidCurrentMacOSVersion(context.macOSVersion)
            )
        }
        guard Self.isValidVersion(requirements.minimumAppVersion),
              Self.isValidVersion(requirements.minimumMacOSVersion)
        else {
            return .indeterminate(.invalidSignedRequirements(modelID: model.id))
        }
        guard requirements.minimumAppVersion == model.minAppVersion,
              artifact.runtime == model.runtime.engine,
              artifact.computeRoute.matches(model.runtime.accelerator)
        else {
            return .indeterminate(.inconsistentSignedMetadata(modelID: model.id))
        }
        guard ProductionModelPolicy.appVersion(
            context.appVersion,
            satisfiesMinimum: requirements.minimumAppVersion
        ) else {
            return .requiresAppUpdate(
                minimumVersion: requirements.minimumAppVersion
            )
        }
        guard ProductionModelPolicy.appVersion(
            context.macOSVersion,
            satisfiesMinimum: requirements.minimumMacOSVersion
        ) else {
            return .requiresMacOSUpdate(
                minimumVersion: requirements.minimumMacOSVersion
            )
        }
        guard let architecture = context.architecture,
              requirements.supportedArchitectures.contains(architecture)
        else {
            return .incompatible(
                .unsupportedArchitecture(
                    current: context.architecture,
                    supported: requirements.supportedArchitectures
                )
            )
        }
        if let minimumMemoryBytes = requirements.minimumMemoryBytes {
            guard context.physicalMemoryBytes > 0 else {
                return .indeterminate(.physicalMemoryUnavailable)
            }
            if context.physicalMemoryBytes < minimumMemoryBytes {
                return .incompatible(
                    .insufficientMemory(
                        requiredBytes: minimumMemoryBytes,
                        availableBytes: context.physicalMemoryBytes
                    )
                )
            }
        }
        guard context.supportedRuntimes.contains(artifact.runtime) else {
            return .incompatible(.unsupportedRuntime(artifact.runtime))
        }
        guard context.supportedArtifactLayouts.contains(
            model.runtime.artifactLayout
        ) else {
            return .incompatible(
                .unsupportedArtifactLayout(model.runtime.artifactLayout)
            )
        }
        guard context.supportedComputeRoutes.contains(artifact.computeRoute) else {
            return .incompatible(
                .unsupportedComputeRoute(artifact.computeRoute)
            )
        }
        return .compatible
    }

    private static func isValidVersion(_ version: String) -> Bool {
        ProductionModelPolicy.appVersion(
            version,
            satisfiesMinimum: "0.0.0"
        )
    }
}

private extension ModelComputeRoute {
    func matches(_ accelerator: ModelAccelerator) -> Bool {
        switch (self, accelerator) {
        case (.gpuViaMetal, .metalGPU),
             (.coreMLNeuralEngine, .coreMLNeuralEngine),
             (.cpuOnly, .cpu):
            true
        default:
            false
        }
    }
}
