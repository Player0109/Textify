public struct ModelCatalogCompatibilityContext: Equatable {
    public let appVersion: String
    public let macOSVersion: String
    public let architecture: ModelArchitecture
    public let physicalMemoryBytes: Int64

    public init(
        appVersion: String,
        macOSVersion: String,
        architecture: ModelArchitecture,
        physicalMemoryBytes: Int64
    ) {
        self.appVersion = appVersion
        self.macOSVersion = macOSVersion
        self.architecture = architecture
        self.physicalMemoryBytes = physicalMemoryBytes
    }
}

public final class ModelCatalogCompatibilityResolver {
    public let context: ModelCatalogCompatibilityContext

    public init(context: ModelCatalogCompatibilityContext) {
        self.context = context
    }

    public func compatibleModelIDs(in manifest: ModelManifest?) -> Set<String>? {
        guard let manifest else {
            return nil
        }
        let artifactsByID = manifest.presentationGraph?.artifacts.reduce(
            into: [String: ModelExactArtifactPresentationNode]()
        ) {
            $0[$1.id] = $1
        } ?? [:]

        return Set(manifest.models.compactMap { model in
            guard ProductionModelPolicy.appVersion(
                context.appVersion,
                satisfiesMinimum: model.minAppVersion
            ) else {
                return nil
            }
            guard let artifact = artifactsByID[model.id] else {
                return model.id
            }
            return isCompatible(with: artifact.compatibility)
                ? model.id
                : nil
        })
    }

    private func isCompatible(
        with requirements: ModelCompatibilityRequirements
    ) -> Bool {
        guard ProductionModelPolicy.appVersion(
            context.appVersion,
            satisfiesMinimum: requirements.minimumAppVersion
        ),
              ProductionModelPolicy.appVersion(
                  context.macOSVersion,
                  satisfiesMinimum: requirements.minimumMacOSVersion
              ),
              requirements.supportedArchitectures.contains(context.architecture)
        else {
            return false
        }
        guard let minimumMemoryBytes = requirements.minimumMemoryBytes else {
            return true
        }
        return context.physicalMemoryBytes >= minimumMemoryBytes
    }
}
