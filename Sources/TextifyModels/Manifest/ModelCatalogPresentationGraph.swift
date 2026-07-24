import Foundation

public enum ModelArtifactContainerFormat: String, Codable, Equatable, Sendable {
    case ggml
    case gguf
    case mlx
    case coreML = "core_ml"
    case onnx
}

public enum ModelNumericFormat: String, Codable, Equatable, Sendable {
    case fp32 = "FP32"
    case f32 = "F32"
    case fp16 = "FP16"
    case f16 = "F16"
    case bf16 = "BF16"
    case int8 = "INT8"
    case eightBit = "8bit"
    case q8_0 = "Q8_0"
    case q5_k_m = "Q5_K_M"
    case q5_1 = "Q5_1"
    case q5_0 = "Q5_0"
    case q4_k_m = "Q4_K_M"
}

public enum ModelComputeRoute: String, Codable, Equatable, CaseIterable, Sendable {
    case gpuViaMetal = "gpu_via_metal"
    case coreMLNeuralEngine = "core_ml_neural_engine"
    case cpuOnly = "cpu_only"
}

public enum ModelArchitecture: String, Codable, Equatable, Sendable {
    case arm64
}

public struct ModelCompatibilityRequirements: Codable, Equatable, Sendable {
    public let minimumAppVersion: String
    public let minimumMacOSVersion: String
    public let supportedArchitectures: [ModelArchitecture]
    public let minimumMemoryBytes: Int64?

    public init(from decoder: Decoder) throws {
        try StrictJSONKeys.validate(
            decoder: decoder,
            allowedKeys: CodingKeys.allCases.map(\.stringValue),
            requiredKeys: CodingKeys.required.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        minimumAppVersion = try container.decode(String.self, forKey: .minimumAppVersion)
        minimumMacOSVersion = try container.decode(String.self, forKey: .minimumMacOSVersion)
        supportedArchitectures = try container.decode(
            [ModelArchitecture].self,
            forKey: .supportedArchitectures
        )
        minimumMemoryBytes = try container.decodeIfPresent(
            Int64.self,
            forKey: .minimumMemoryBytes
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case minimumAppVersion
        case minimumMacOSVersion
        case supportedArchitectures
        case minimumMemoryBytes

        static let required: [CodingKeys] = [
            .minimumAppVersion,
            .minimumMacOSVersion,
            .supportedArchitectures,
        ]
    }
}

public struct ModelProviderPresentationMetadata: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String

    public init(from decoder: Decoder) throws {
        try StrictJSONKeys.validate(
            decoder: decoder,
            allowedKeys: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case displayName
    }
}

public struct ModelFamilyPresentationMetadata: Codable, Equatable, Sendable {
    public let displayName: String
    public let description: String
    public let provider: ModelProviderPresentationMetadata
    public let curatedRank: Int

    public init(from decoder: Decoder) throws {
        try StrictJSONKeys.validate(
            decoder: decoder,
            allowedKeys: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decode(String.self, forKey: .displayName)
        description = try container.decode(String.self, forKey: .description)
        provider = try container.decode(
            ModelProviderPresentationMetadata.self,
            forKey: .provider
        )
        curatedRank = try container.decode(Int.self, forKey: .curatedRank)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case displayName
        case description
        case provider
        case curatedRank
    }
}

public struct ModelCheckpointPresentationMetadata: Codable, Equatable, Sendable {
    public let displayName: String
    public let description: String
    public let curatedRank: Int

    public init(from decoder: Decoder) throws {
        try StrictJSONKeys.validate(
            decoder: decoder,
            allowedKeys: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decode(String.self, forKey: .displayName)
        description = try container.decode(String.self, forKey: .description)
        curatedRank = try container.decode(Int.self, forKey: .curatedRank)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case displayName
        case description
        case curatedRank
    }
}

public struct ModelExactArtifactPresentationMetadata: Codable, Equatable, Sendable {
    public let displayName: String
    public let curatedRank: Int
    public let comparisonGroupID: String?

    public init(from decoder: Decoder) throws {
        try StrictJSONKeys.validate(
            decoder: decoder,
            allowedKeys: CodingKeys.allCases.map(\.stringValue),
            requiredKeys: CodingKeys.required.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try container.decode(String.self, forKey: .displayName)
        curatedRank = try container.decode(Int.self, forKey: .curatedRank)
        comparisonGroupID = try container.decodeIfPresent(
            String.self,
            forKey: .comparisonGroupID
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case displayName
        case curatedRank
        case comparisonGroupID

        static let required: [CodingKeys] = [
            .displayName,
            .curatedRank,
        ]
    }
}

public struct ModelFamilyPresentationNode: Codable, Equatable, Sendable {
    public let id: String
    public let purpose: ModelPurpose
    public let checkpointIDs: [String]
    public let presentation: ModelFamilyPresentationMetadata

    public init(from decoder: Decoder) throws {
        try StrictJSONKeys.validate(
            decoder: decoder,
            allowedKeys: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        purpose = try container.decode(ModelPurpose.self, forKey: .purpose)
        checkpointIDs = try container.decode([String].self, forKey: .checkpointIDs)
        presentation = try container.decode(
            ModelFamilyPresentationMetadata.self,
            forKey: .presentation
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case purpose
        case checkpointIDs
        case presentation
    }
}

public struct ModelCheckpointPresentationNode: Codable, Equatable, Sendable {
    public let id: String
    public let purpose: ModelPurpose
    public let artifactIDs: [String]
    public let recommendedArtifactID: String
    public let fallbackArtifactIDs: [String]
    public let presentation: ModelCheckpointPresentationMetadata

    public init(from decoder: Decoder) throws {
        try StrictJSONKeys.validate(
            decoder: decoder,
            allowedKeys: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        purpose = try container.decode(ModelPurpose.self, forKey: .purpose)
        artifactIDs = try container.decode([String].self, forKey: .artifactIDs)
        recommendedArtifactID = try container.decode(
            String.self,
            forKey: .recommendedArtifactID
        )
        fallbackArtifactIDs = try container.decode(
            [String].self,
            forKey: .fallbackArtifactIDs
        )
        presentation = try container.decode(
            ModelCheckpointPresentationMetadata.self,
            forKey: .presentation
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case purpose
        case artifactIDs
        case recommendedArtifactID
        case fallbackArtifactIDs
        case presentation
    }
}

public struct ModelExactArtifactPresentationNode: Codable, Equatable, Sendable {
    public let id: String
    public let purpose: ModelPurpose
    public let artifactFormat: ModelArtifactContainerFormat
    public let numericFormat: ModelNumericFormat
    public let runtime: TranscriptionEngine
    public let computeRoute: ModelComputeRoute
    public let compatibility: ModelCompatibilityRequirements
    public let presentation: ModelExactArtifactPresentationMetadata

    public init(from decoder: Decoder) throws {
        try StrictJSONKeys.validate(
            decoder: decoder,
            allowedKeys: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        purpose = try container.decode(ModelPurpose.self, forKey: .purpose)
        artifactFormat = try container.decode(
            ModelArtifactContainerFormat.self,
            forKey: .artifactFormat
        )
        numericFormat = try container.decode(
            ModelNumericFormat.self,
            forKey: .numericFormat
        )
        runtime = try container.decode(TranscriptionEngine.self, forKey: .runtime)
        computeRoute = try container.decode(ModelComputeRoute.self, forKey: .computeRoute)
        compatibility = try container.decode(
            ModelCompatibilityRequirements.self,
            forKey: .compatibility
        )
        presentation = try container.decode(
            ModelExactArtifactPresentationMetadata.self,
            forKey: .presentation
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case purpose
        case artifactFormat
        case numericFormat
        case runtime
        case computeRoute
        case compatibility
        case presentation
    }
}

public struct ModelCatalogPresentationGraph: Codable, Equatable, Sendable {
    public let families: [ModelFamilyPresentationNode]
    public let checkpoints: [ModelCheckpointPresentationNode]
    public let artifacts: [ModelExactArtifactPresentationNode]

    public init(from decoder: Decoder) throws {
        try StrictJSONKeys.validate(
            decoder: decoder,
            allowedKeys: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        families = try container.decode([ModelFamilyPresentationNode].self, forKey: .families)
        checkpoints = try container.decode(
            [ModelCheckpointPresentationNode].self,
            forKey: .checkpoints
        )
        artifacts = try container.decode(
            [ModelExactArtifactPresentationNode].self,
            forKey: .artifacts
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case families
        case checkpoints
        case artifacts
    }
}

public enum ModelCatalogGraphValidationError: Error, Equatable, Sendable {
    case missingPresentationGraph
    case invalidIdentity(String)
    case invalidPresentation(recordID: String)
    case duplicateID(String)
    case duplicateCuratedRank(ownerID: String, rank: Int)
    case missingReference(ownerID: String, referenceID: String)
    case multipleOwnership(recordID: String)
    case purposeMismatch(recordID: String)
    case unreachableRecord(String)
    case invalidRecommendation(checkpointID: String, artifactID: String)
    case invalidFallback(checkpointID: String, artifactID: String)
    case runtimeMismatch(artifactID: String)
    case computeRouteMismatch(artifactID: String)
    case compatibilityMismatch(artifactID: String)
}

extension ModelCatalogPresentationGraph {
    func validate(operationalModels: [ModelEntry]) throws {
        try validateUniqueIdentitiesAndPresentation()

        let checkpointsByID = Dictionary(uniqueKeysWithValues: checkpoints.map { ($0.id, $0) })
        let artifactsByID = Dictionary(uniqueKeysWithValues: artifacts.map { ($0.id, $0) })
        let modelsByID = Dictionary(uniqueKeysWithValues: operationalModels.map { ($0.id, $0) })

        var checkpointOwners: [String: String] = [:]
        for family in families {
            guard !family.checkpointIDs.isEmpty else {
                throw ModelCatalogGraphValidationError.invalidPresentation(recordID: family.id)
            }
            try validateUniqueRanks(
                family.checkpointIDs.compactMap { checkpointsByID[$0]?.presentation.curatedRank },
                ownerID: family.id
            )
            for checkpointID in family.checkpointIDs {
                guard let checkpoint = checkpointsByID[checkpointID] else {
                    throw ModelCatalogGraphValidationError.missingReference(
                        ownerID: family.id,
                        referenceID: checkpointID
                    )
                }
                guard checkpointOwners.updateValue(family.id, forKey: checkpointID) == nil else {
                    throw ModelCatalogGraphValidationError.multipleOwnership(
                        recordID: checkpointID
                    )
                }
                guard checkpoint.purpose == family.purpose else {
                    throw ModelCatalogGraphValidationError.purposeMismatch(
                        recordID: checkpointID
                    )
                }
            }
        }

        for checkpoint in checkpoints where checkpointOwners[checkpoint.id] == nil {
            throw ModelCatalogGraphValidationError.unreachableRecord(checkpoint.id)
        }

        var artifactOwners: [String: String] = [:]
        for checkpoint in checkpoints {
            guard !checkpoint.artifactIDs.isEmpty else {
                throw ModelCatalogGraphValidationError.invalidPresentation(
                    recordID: checkpoint.id
                )
            }
            try validateUniqueRanks(
                checkpoint.artifactIDs.compactMap { artifactsByID[$0]?.presentation.curatedRank },
                ownerID: checkpoint.id
            )
            for artifactID in checkpoint.artifactIDs {
                guard let artifact = artifactsByID[artifactID] else {
                    throw ModelCatalogGraphValidationError.missingReference(
                        ownerID: checkpoint.id,
                        referenceID: artifactID
                    )
                }
                guard artifactOwners.updateValue(checkpoint.id, forKey: artifactID) == nil else {
                    throw ModelCatalogGraphValidationError.multipleOwnership(recordID: artifactID)
                }
                guard artifact.purpose == checkpoint.purpose else {
                    throw ModelCatalogGraphValidationError.purposeMismatch(recordID: artifactID)
                }
            }

            guard checkpoint.artifactIDs.contains(checkpoint.recommendedArtifactID) else {
                throw ModelCatalogGraphValidationError.invalidRecommendation(
                    checkpointID: checkpoint.id,
                    artifactID: checkpoint.recommendedArtifactID
                )
            }
            var fallbackIDs = Set<String>()
            for artifactID in checkpoint.fallbackArtifactIDs {
                guard artifactID != checkpoint.recommendedArtifactID,
                      checkpoint.artifactIDs.contains(artifactID),
                      fallbackIDs.insert(artifactID).inserted
                else {
                    throw ModelCatalogGraphValidationError.invalidFallback(
                        checkpointID: checkpoint.id,
                        artifactID: artifactID
                    )
                }
            }
        }

        for artifact in artifacts where artifactOwners[artifact.id] == nil {
            throw ModelCatalogGraphValidationError.unreachableRecord(artifact.id)
        }

        for artifact in artifacts {
            guard let model = modelsByID[artifact.id] else {
                throw ModelCatalogGraphValidationError.missingReference(
                    ownerID: artifact.id,
                    referenceID: artifact.id
                )
            }
            guard artifact.purpose == model.purpose else {
                throw ModelCatalogGraphValidationError.purposeMismatch(recordID: artifact.id)
            }
            guard artifact.runtime == model.runtime.engine else {
                throw ModelCatalogGraphValidationError.runtimeMismatch(artifactID: artifact.id)
            }
            guard artifact.computeRoute.matches(model.runtime.accelerator) else {
                throw ModelCatalogGraphValidationError.computeRouteMismatch(
                    artifactID: artifact.id
                )
            }
            guard artifact.compatibility.minimumAppVersion == model.minAppVersion,
                  ProductionModelPolicy.appVersion(
                      artifact.compatibility.minimumAppVersion,
                      satisfiesMinimum: "0.0.0"
                  ),
                  ProductionModelPolicy.appVersion(
                      artifact.compatibility.minimumMacOSVersion,
                      satisfiesMinimum: "0.0.0"
                  ),
                  !artifact.compatibility.supportedArchitectures.isEmpty,
                  artifact.compatibility.minimumMemoryBytes.map({ $0 > 0 }) ?? true
            else {
                throw ModelCatalogGraphValidationError.compatibilityMismatch(
                    artifactID: artifact.id
                )
            }
        }

        let presentedArtifactIDs = Set(artifacts.map(\.id))
        for model in operationalModels where !presentedArtifactIDs.contains(model.id) {
            throw ModelCatalogGraphValidationError.unreachableRecord(model.id)
        }
    }

    private func validateUniqueIdentitiesAndPresentation() throws {
        var identities = Set<String>()
        for family in families {
            try validateUniqueIdentity(family.id, observed: &identities)
            try validatePresentation(
                recordID: family.id,
                displayName: family.presentation.displayName,
                description: family.presentation.description,
                curatedRank: family.presentation.curatedRank
            )
            try validateIdentity(family.presentation.provider.id)
            guard !family.presentation.provider.displayName
                .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                throw ModelCatalogGraphValidationError.invalidPresentation(
                    recordID: family.id
                )
            }
        }
        try validateUniqueRanks(
            families.map(\.presentation.curatedRank),
            ownerID: "presentationGraph"
        )

        for checkpoint in checkpoints {
            try validateUniqueIdentity(checkpoint.id, observed: &identities)
            try validatePresentation(
                recordID: checkpoint.id,
                displayName: checkpoint.presentation.displayName,
                description: checkpoint.presentation.description,
                curatedRank: checkpoint.presentation.curatedRank
            )
        }

        for artifact in artifacts {
            try validateUniqueIdentity(artifact.id, observed: &identities)
            let comparisonGroupID = artifact.presentation.comparisonGroupID?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard artifact.presentation.curatedRank >= 0,
                  !artifact.presentation.displayName
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  comparisonGroupID == nil || comparisonGroupID?.isEmpty == false
            else {
                throw ModelCatalogGraphValidationError.invalidPresentation(
                    recordID: artifact.id
                )
            }
        }
    }

    private func validateIdentity(_ id: String) throws {
        guard !id.isEmpty,
              id.unicodeScalars.allSatisfy({
                  CharacterSet.alphanumerics.contains($0)
                      || CharacterSet(charactersIn: "-_.:").contains($0)
              })
        else {
            throw ModelCatalogGraphValidationError.invalidIdentity(id)
        }
    }

    private func validateUniqueIdentity(
        _ id: String,
        observed: inout Set<String>
    ) throws {
        try validateIdentity(id)
        guard observed.insert(id).inserted else {
            throw ModelCatalogGraphValidationError.duplicateID(id)
        }
    }

    private func validatePresentation(
        recordID: String,
        displayName: String,
        description: String,
        curatedRank: Int
    ) throws {
        guard curatedRank >= 0,
              !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw ModelCatalogGraphValidationError.invalidPresentation(recordID: recordID)
        }
    }

    private func validateUniqueRanks(_ ranks: [Int], ownerID: String) throws {
        var observed = Set<Int>()
        for rank in ranks where !observed.insert(rank).inserted {
            throw ModelCatalogGraphValidationError.duplicateCuratedRank(
                ownerID: ownerID,
                rank: rank
            )
        }
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
