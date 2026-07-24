import CryptoKit
import Foundation

public enum ModelManifestDecodingError: Error, Equatable {
    case unsupportedManifestVersion(Int)
}

enum ModelManifestSchemaVersion: Int, CaseIterable {
    case v1 = 1
    case v2 = 2
    case v3 = 3

    var contentType: String {
        "application/vnd.textify.model-manifest+json;version=\(rawValue)"
    }

    var requiresPresentationGraph: Bool {
        self == .v3
    }

    init?(contentType: String) {
        guard let version = Self.allCases.first(where: { $0.contentType == contentType }) else {
            return nil
        }
        self = version
    }
}

public struct ModelManifest: Codable, Equatable, Sendable {
    public let manifestVersion: Int
    public let generatedAt: String
    public let models: [ModelEntry]
    public let presentationGraph: ModelCatalogPresentationGraph?

    public static func decode(_ data: Data) throws -> ModelManifest {
        try JSONDecoder().decode(ModelManifest.self, from: data)
    }

    public init(
        manifestVersion: Int,
        generatedAt: String,
        models: [ModelEntry],
        presentationGraph: ModelCatalogPresentationGraph? = nil
    ) {
        self.manifestVersion = manifestVersion
        self.generatedAt = generatedAt
        self.models = models
        self.presentationGraph = presentationGraph
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedVersion = try container.decode(Int.self, forKey: .manifestVersion)
        guard let schemaVersion = ModelManifestSchemaVersion(rawValue: decodedVersion) else {
            throw ModelManifestDecodingError.unsupportedManifestVersion(decodedVersion)
        }
        let requiredKeys: [CodingKeys] = schemaVersion.requiresPresentationGraph
            ? CodingKeys.allCases
            : [.manifestVersion, .generatedAt, .models]
        try StrictJSONKeys.validate(
            decoder: decoder,
            allowedKeys: requiredKeys.map(\.stringValue)
        )
        manifestVersion = decodedVersion
        generatedAt = try container.decode(String.self, forKey: .generatedAt)
        models = try container.decode([ModelEntry].self, forKey: .models)
        if schemaVersion.requiresPresentationGraph {
            presentationGraph = try container.decode(
                ModelCatalogPresentationGraph.self,
                forKey: .presentationGraph
            )
        } else {
            presentationGraph = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(manifestVersion, forKey: .manifestVersion)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(models, forKey: .models)
        if ModelManifestSchemaVersion(rawValue: manifestVersion)?.requiresPresentationGraph == true {
            try container.encode(presentationGraph, forKey: .presentationGraph)
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case manifestVersion
        case generatedAt
        case models
        case presentationGraph
    }
}

public enum ModelPurpose: String, Codable, Equatable, Hashable, Sendable {
    case transcription
    case voiceCleaning = "voice_cleaning"
}

public enum TranscriptionEngine: String, Codable, Equatable, CaseIterable, Sendable {
    case whisperCpp = "whisper_cpp"
    case fluidAudioParakeet = "fluid_audio_parakeet"
    case fluidAudioParaformer = "fluid_audio_paraformer"
    case sherpaOnnx = "sherpa_onnx"
    case transcribeCpp = "transcribe_cpp"
    case mlxAudio = "mlx_audio"
    case liteRTLM = "litert_lm"
}

public enum ModelAccelerator: String, Codable, Equatable, Sendable {
    case metalGPU = "metal_gpu"
    case coreMLNeuralEngine = "coreml_neural_engine"
    case cpu
}

public enum ModelArtifactLayout: String, Codable, Equatable, CaseIterable, Sendable {
    case singleFile = "single_file"
    case modelDirectory = "model_directory"
}

public struct ModelRuntimeDescriptor: Codable, Equatable, Sendable {
    public let engine: TranscriptionEngine
    public let variant: String
    public let accelerator: ModelAccelerator
    public let artifactLayout: ModelArtifactLayout

    public init(
        engine: TranscriptionEngine,
        variant: String,
        accelerator: ModelAccelerator,
        artifactLayout: ModelArtifactLayout
    ) {
        self.engine = engine
        self.variant = variant
        self.accelerator = accelerator
        self.artifactLayout = artifactLayout
    }

    public static let legacyWhisper = ModelRuntimeDescriptor(
        engine: .whisperCpp,
        variant: "whisper",
        accelerator: .metalGPU,
        artifactLayout: .singleFile
    )

    public init(from decoder: Decoder) throws {
        try StrictJSONKeys.validate(
            decoder: decoder,
            allowedKeys: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        engine = try container.decode(TranscriptionEngine.self, forKey: .engine)
        variant = try container.decode(String.self, forKey: .variant)
        accelerator = try container.decode(ModelAccelerator.self, forKey: .accelerator)
        artifactLayout = try container.decode(ModelArtifactLayout.self, forKey: .artifactLayout)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case engine
        case variant
        case accelerator
        case artifactLayout
    }
}

public struct ModelCapabilities: Codable, Equatable, Sendable {
    public let languages: [String]
    public let supportsTranslation: Bool
    public let supportsCustomVocabulary: Bool

    public init(
        languages: [String],
        supportsTranslation: Bool,
        supportsCustomVocabulary: Bool
    ) {
        self.languages = languages
        self.supportsTranslation = supportsTranslation
        self.supportsCustomVocabulary = supportsCustomVocabulary
    }

    public static let legacyEnglishWhisper = ModelCapabilities(
        languages: ["en"],
        supportsTranslation: false,
        supportsCustomVocabulary: false
    )

    public init(from decoder: Decoder) throws {
        try StrictJSONKeys.validate(
            decoder: decoder,
            allowedKeys: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        languages = try container.decode([String].self, forKey: .languages)
        supportsTranslation = try container.decode(Bool.self, forKey: .supportsTranslation)
        supportsCustomVocabulary = try container.decode(Bool.self, forKey: .supportsCustomVocabulary)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case languages
        case supportsTranslation
        case supportsCustomVocabulary
    }
}

public struct ModelUserPresentation: Codable, Equatable, Sendable {
    public let expectedFinalization: String
    public let accuracyTradeoff: String
    public let requirements: String

    public init(
        expectedFinalization: String,
        accuracyTradeoff: String,
        requirements: String
    ) {
        self.expectedFinalization = expectedFinalization
        self.accuracyTradeoff = accuracyTradeoff
        self.requirements = requirements
    }

    public init(from decoder: Decoder) throws {
        try StrictJSONKeys.validate(
            decoder: decoder,
            allowedKeys: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        expectedFinalization = try container.decode(String.self, forKey: .expectedFinalization)
        accuracyTradeoff = try container.decode(String.self, forKey: .accuracyTradeoff)
        requirements = try container.decode(String.self, forKey: .requirements)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case expectedFinalization
        case accuracyTradeoff
        case requirements
    }
}

public struct ModelEntry: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let tier: String
    public let description: String
    public let sizeBytes: Int64
    public let files: [ModelFile]
    public let licenses: [ModelLicense]
    public let provenance: ModelProvenance
    public let runtimeParameters: RuntimeParameters
    public let hallucinationThresholds: HallucinationThresholds
    public let minAppVersion: String
    public let runtime: ModelRuntimeDescriptor
    public let capabilities: ModelCapabilities
    public let presentation: ModelUserPresentation?
    public let purpose: ModelPurpose
    public let benchmark: ModelBenchmarkRating?

    public init(
        id: String,
        displayName: String,
        tier: String,
        description: String,
        sizeBytes: Int64,
        files: [ModelFile],
        licenses: [ModelLicense],
        provenance: ModelProvenance,
        runtimeParameters: RuntimeParameters,
        hallucinationThresholds: HallucinationThresholds,
        minAppVersion: String
    ) {
        self.init(
            id: id,
            displayName: displayName,
            tier: tier,
            description: description,
            sizeBytes: sizeBytes,
            files: files,
            licenses: licenses,
            provenance: provenance,
            runtimeParameters: runtimeParameters,
            hallucinationThresholds: hallucinationThresholds,
            minAppVersion: minAppVersion,
            runtime: .legacyWhisper,
            capabilities: .legacyEnglishWhisper,
            presentation: nil,
            purpose: .transcription
        )
    }

    public init(
        id: String,
        displayName: String,
        tier: String,
        description: String,
        sizeBytes: Int64,
        files: [ModelFile],
        licenses: [ModelLicense],
        provenance: ModelProvenance,
        runtimeParameters: RuntimeParameters,
        hallucinationThresholds: HallucinationThresholds,
        minAppVersion: String,
        runtime: ModelRuntimeDescriptor,
        capabilities: ModelCapabilities
    ) {
        self.init(
            id: id,
            displayName: displayName,
            tier: tier,
            description: description,
            sizeBytes: sizeBytes,
            files: files,
            licenses: licenses,
            provenance: provenance,
            runtimeParameters: runtimeParameters,
            hallucinationThresholds: hallucinationThresholds,
            minAppVersion: minAppVersion,
            runtime: runtime,
            capabilities: capabilities,
            presentation: nil,
            purpose: .transcription
        )
    }

    public init(
        id: String,
        displayName: String,
        tier: String,
        description: String,
        sizeBytes: Int64,
        files: [ModelFile],
        licenses: [ModelLicense],
        provenance: ModelProvenance,
        runtimeParameters: RuntimeParameters,
        hallucinationThresholds: HallucinationThresholds,
        minAppVersion: String,
        runtime: ModelRuntimeDescriptor,
        capabilities: ModelCapabilities,
        presentation: ModelUserPresentation?,
        purpose: ModelPurpose = .transcription
    ) {
        self.init(
            id: id,
            displayName: displayName,
            tier: tier,
            description: description,
            sizeBytes: sizeBytes,
            files: files,
            licenses: licenses,
            provenance: provenance,
            runtimeParameters: runtimeParameters,
            hallucinationThresholds: hallucinationThresholds,
            minAppVersion: minAppVersion,
            runtime: runtime,
            capabilities: capabilities,
            presentation: presentation,
            purpose: purpose,
            benchmark: nil
        )
    }

    public init(
        id: String,
        displayName: String,
        tier: String,
        description: String,
        sizeBytes: Int64,
        files: [ModelFile],
        licenses: [ModelLicense],
        provenance: ModelProvenance,
        runtimeParameters: RuntimeParameters,
        hallucinationThresholds: HallucinationThresholds,
        minAppVersion: String,
        runtime: ModelRuntimeDescriptor,
        capabilities: ModelCapabilities,
        presentation: ModelUserPresentation?,
        purpose: ModelPurpose,
        benchmark: ModelBenchmarkRating?
    ) {
        self.id = id
        self.displayName = displayName
        self.tier = tier
        self.description = description
        self.sizeBytes = sizeBytes
        self.files = files
        self.licenses = licenses
        self.provenance = provenance
        self.runtimeParameters = runtimeParameters
        self.hallucinationThresholds = hallucinationThresholds
        self.minAppVersion = minAppVersion
        self.runtime = runtime
        self.capabilities = capabilities
        self.presentation = presentation
        self.purpose = purpose
        self.benchmark = benchmark
    }

    public init(from decoder: Decoder) throws {
        try StrictJSONKeys.validate(
            decoder: decoder,
            allowedKeys: CodingKeys.allCases.map(\.stringValue),
            requiredKeys: CodingKeys.legacyRequired.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        tier = try container.decode(String.self, forKey: .tier)
        description = try container.decode(String.self, forKey: .description)
        sizeBytes = try container.decode(Int64.self, forKey: .sizeBytes)
        files = try container.decode([ModelFile].self, forKey: .files)
        licenses = try container.decode([ModelLicense].self, forKey: .licenses)
        provenance = try container.decode(ModelProvenance.self, forKey: .provenance)
        runtimeParameters = try container.decode(RuntimeParameters.self, forKey: .runtimeParameters)
        hallucinationThresholds = try container.decode(HallucinationThresholds.self, forKey: .hallucinationThresholds)
        minAppVersion = try container.decode(String.self, forKey: .minAppVersion)
        runtime = try container.decodeIfPresent(ModelRuntimeDescriptor.self, forKey: .runtime) ?? .legacyWhisper
        capabilities = try container.decodeIfPresent(ModelCapabilities.self, forKey: .capabilities) ?? .legacyEnglishWhisper
        presentation = try container.decodeIfPresent(ModelUserPresentation.self, forKey: .presentation)
        purpose = try container.decodeIfPresent(ModelPurpose.self, forKey: .purpose) ?? .transcription
        benchmark = try container.decodeIfPresent(ModelBenchmarkRating.self, forKey: .benchmark)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case displayName
        case tier
        case description
        case sizeBytes
        case files
        case licenses
        case provenance
        case runtimeParameters
        case hallucinationThresholds
        case minAppVersion
        case runtime
        case capabilities
        case presentation
        case purpose
        case benchmark

        static let legacyRequired: [CodingKeys] = [
            .id,
            .displayName,
            .tier,
            .description,
            .sizeBytes,
            .files,
            .licenses,
            .provenance,
            .runtimeParameters,
            .hallucinationThresholds,
            .minAppVersion
        ]
    }

    public func artifactFingerprint() -> String {
        let canonical = files
            .sorted {
                ($0.relativePath ?? $0.filename) < ($1.relativePath ?? $1.filename)
            }
            .map {
                "\($0.relativePath ?? $0.filename)\t\($0.sha256)\t\($0.sizeBytes)\n"
            }
            .joined()
        return SHA256.hash(data: Data(canonical.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

public struct ModelFile: Codable, Equatable, Sendable {
    public let filename: String
    public let relativePath: String?
    public let url: String
    public let sha256: String
    public let sizeBytes: Int64

    public init(filename: String, url: String, sha256: String, sizeBytes: Int64) {
        self.init(
            filename: filename,
            relativePath: nil,
            url: url,
            sha256: sha256,
            sizeBytes: sizeBytes
        )
    }

    public init(
        filename: String,
        relativePath: String?,
        url: String,
        sha256: String,
        sizeBytes: Int64
    ) {
        self.filename = filename
        self.relativePath = relativePath
        self.url = url
        self.sha256 = sha256
        self.sizeBytes = sizeBytes
    }

    public init(from decoder: Decoder) throws {
        try StrictJSONKeys.validate(
            decoder: decoder,
            allowedKeys: CodingKeys.allCases.map(\.stringValue),
            requiredKeys: CodingKeys.legacyRequired.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        filename = try container.decode(String.self, forKey: .filename)
        relativePath = try container.decodeIfPresent(String.self, forKey: .relativePath)
        url = try container.decode(String.self, forKey: .url)
        sha256 = try container.decode(String.self, forKey: .sha256)
        sizeBytes = try container.decode(Int64.self, forKey: .sizeBytes)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case filename
        case relativePath
        case url
        case sha256
        case sizeBytes

        static let legacyRequired: [CodingKeys] = [
            .filename,
            .url,
            .sha256,
            .sizeBytes
        ]
    }
}

public struct ModelLicense: Codable, Equatable, Sendable {
    public let scope: String
    public let spdxId: String
    public let name: String
    public let licenseTextUrl: String

    public init(scope: String, spdxId: String, name: String, licenseTextUrl: String) {
        self.scope = scope
        self.spdxId = spdxId
        self.name = name
        self.licenseTextUrl = licenseTextUrl
    }

    public init(from decoder: Decoder) throws {
        try StrictJSONKeys.validate(
            decoder: decoder,
            allowedKeys: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scope = try container.decode(String.self, forKey: .scope)
        spdxId = try container.decode(String.self, forKey: .spdxId)
        name = try container.decode(String.self, forKey: .name)
        licenseTextUrl = try container.decode(String.self, forKey: .licenseTextUrl)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case scope
        case spdxId
        case name
        case licenseTextUrl
    }
}

public struct ModelProvenance: Codable, Equatable, Sendable {
    public let sourceName: String
    public let sourceUrl: String
    public let sourceRevision: String
    public let sourceFile: String
    public let originalModelName: String
    public let originalModelUrl: String
    public let mirroredBy: String
    public let mirroredAt: String

    public init(
        sourceName: String,
        sourceUrl: String,
        sourceRevision: String,
        sourceFile: String,
        originalModelName: String,
        originalModelUrl: String,
        mirroredBy: String,
        mirroredAt: String
    ) {
        self.sourceName = sourceName
        self.sourceUrl = sourceUrl
        self.sourceRevision = sourceRevision
        self.sourceFile = sourceFile
        self.originalModelName = originalModelName
        self.originalModelUrl = originalModelUrl
        self.mirroredBy = mirroredBy
        self.mirroredAt = mirroredAt
    }

    public init(from decoder: Decoder) throws {
        try StrictJSONKeys.validate(
            decoder: decoder,
            allowedKeys: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceName = try container.decode(String.self, forKey: .sourceName)
        sourceUrl = try container.decode(String.self, forKey: .sourceUrl)
        sourceRevision = try container.decode(String.self, forKey: .sourceRevision)
        sourceFile = try container.decode(String.self, forKey: .sourceFile)
        originalModelName = try container.decode(String.self, forKey: .originalModelName)
        originalModelUrl = try container.decode(String.self, forKey: .originalModelUrl)
        mirroredBy = try container.decode(String.self, forKey: .mirroredBy)
        mirroredAt = try container.decode(String.self, forKey: .mirroredAt)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case sourceName
        case sourceUrl
        case sourceRevision
        case sourceFile
        case originalModelName
        case originalModelUrl
        case mirroredBy
        case mirroredAt
    }
}

public struct RuntimeParameters: Codable, Equatable, Sendable {
    public let language: String
    public let detectLanguage: Bool
    public let translate: Bool
    public let strategy: String
    public let beamSize: Int
    public let bestOf: Int
    public let temperature: Double
    public let temperatureFallback: [Double]
    public let noContext: Bool
    public let tokenTimestamps: Bool
    public let maxAudioSeconds: Int

    public init(
        language: String,
        detectLanguage: Bool,
        translate: Bool,
        strategy: String,
        beamSize: Int,
        bestOf: Int,
        temperature: Double,
        temperatureFallback: [Double],
        noContext: Bool,
        tokenTimestamps: Bool,
        maxAudioSeconds: Int
    ) {
        self.language = language
        self.detectLanguage = detectLanguage
        self.translate = translate
        self.strategy = strategy
        self.beamSize = beamSize
        self.bestOf = bestOf
        self.temperature = temperature
        self.temperatureFallback = temperatureFallback
        self.noContext = noContext
        self.tokenTimestamps = tokenTimestamps
        self.maxAudioSeconds = maxAudioSeconds
    }

    public static let legacyEnglishWhisper = RuntimeParameters(
        language: "en",
        detectLanguage: false,
        translate: false,
        strategy: "greedy",
        beamSize: 1,
        bestOf: 1,
        temperature: 0,
        temperatureFallback: [],
        noContext: true,
        tokenTimestamps: false,
        maxAudioSeconds: 60
    )

    public init(from decoder: Decoder) throws {
        try StrictJSONKeys.validate(
            decoder: decoder,
            allowedKeys: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        language = try container.decode(String.self, forKey: .language)
        detectLanguage = try container.decode(Bool.self, forKey: .detectLanguage)
        translate = try container.decode(Bool.self, forKey: .translate)
        strategy = try container.decode(String.self, forKey: .strategy)
        beamSize = try container.decode(Int.self, forKey: .beamSize)
        bestOf = try container.decode(Int.self, forKey: .bestOf)
        temperature = try container.decode(Double.self, forKey: .temperature)
        temperatureFallback = try container.decode([Double].self, forKey: .temperatureFallback)
        noContext = try container.decode(Bool.self, forKey: .noContext)
        tokenTimestamps = try container.decode(Bool.self, forKey: .tokenTimestamps)
        maxAudioSeconds = try container.decode(Int.self, forKey: .maxAudioSeconds)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case language
        case detectLanguage
        case translate
        case strategy
        case beamSize
        case bestOf
        case temperature
        case temperatureFallback
        case noContext
        case tokenTimestamps
        case maxAudioSeconds
    }
}

public struct HallucinationThresholds: Codable, Equatable, Sendable {
    public let noSpeechProbabilityMax: Double
    public let avgLogProbabilityMin: Double
    public let compressionRatioMax: Double

    public init(
        noSpeechProbabilityMax: Double,
        avgLogProbabilityMin: Double,
        compressionRatioMax: Double
    ) {
        self.noSpeechProbabilityMax = noSpeechProbabilityMax
        self.avgLogProbabilityMin = avgLogProbabilityMin
        self.compressionRatioMax = compressionRatioMax
    }

    public init(from decoder: Decoder) throws {
        try StrictJSONKeys.validate(
            decoder: decoder,
            allowedKeys: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        noSpeechProbabilityMax = try container.decode(Double.self, forKey: .noSpeechProbabilityMax)
        avgLogProbabilityMin = try container.decode(Double.self, forKey: .avgLogProbabilityMin)
        compressionRatioMax = try container.decode(Double.self, forKey: .compressionRatioMax)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case noSpeechProbabilityMax
        case avgLogProbabilityMin
        case compressionRatioMax
    }
}

enum JSONValue: Decodable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: Decoder) throws {
        if let object = try? [String: JSONValue](from: decoder) {
            self = .object(object)
            return
        }

        if let array = try? [JSONValue](from: decoder) {
            self = .array(array)
            return
        }

        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }
}

enum StrictJSONKeys {
    static func validate(
        decoder: Decoder,
        allowedKeys: [String],
        requiredKeys: [String]? = nil
    ) throws {
        let object = try [String: JSONValue](from: decoder)
        let observed = Set(object.keys)
        let allowed = Set(allowedKeys)
        let unknown = observed.subtracting(allowed).sorted()
        let required = Set(requiredKeys ?? allowedKeys)
        let missing = required.subtracting(observed).sorted()

        if !unknown.isEmpty {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown keys: \(unknown.joined(separator: ", "))"
                )
            )
        }

        if !missing.isEmpty {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Missing keys: \(missing.joined(separator: ", "))"
                )
            )
        }
    }
}
