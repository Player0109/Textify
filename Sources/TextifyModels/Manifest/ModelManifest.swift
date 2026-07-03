import Foundation

public struct ModelManifest: Codable, Equatable {
    public let manifestVersion: Int
    public let generatedAt: String
    public let models: [ModelEntry]

    public static func decode(_ data: Data) throws -> ModelManifest {
        try JSONDecoder().decode(ModelManifest.self, from: data)
    }

    public init(manifestVersion: Int, generatedAt: String, models: [ModelEntry]) {
        self.manifestVersion = manifestVersion
        self.generatedAt = generatedAt
        self.models = models
    }

    public init(from decoder: Decoder) throws {
        try StrictJSONKeys.validate(
            decoder: decoder,
            allowedKeys: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        manifestVersion = try container.decode(Int.self, forKey: .manifestVersion)
        generatedAt = try container.decode(String.self, forKey: .generatedAt)
        models = try container.decode([ModelEntry].self, forKey: .models)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case manifestVersion
        case generatedAt
        case models
    }
}

public struct ModelEntry: Codable, Equatable {
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
    }

    public init(from decoder: Decoder) throws {
        try StrictJSONKeys.validate(
            decoder: decoder,
            allowedKeys: CodingKeys.allCases.map(\.stringValue)
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
    }
}

public struct ModelFile: Codable, Equatable {
    public let filename: String
    public let url: String
    public let sha256: String
    public let sizeBytes: Int64

    public init(filename: String, url: String, sha256: String, sizeBytes: Int64) {
        self.filename = filename
        self.url = url
        self.sha256 = sha256
        self.sizeBytes = sizeBytes
    }

    public init(from decoder: Decoder) throws {
        try StrictJSONKeys.validate(
            decoder: decoder,
            allowedKeys: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        filename = try container.decode(String.self, forKey: .filename)
        url = try container.decode(String.self, forKey: .url)
        sha256 = try container.decode(String.self, forKey: .sha256)
        sizeBytes = try container.decode(Int64.self, forKey: .sizeBytes)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case filename
        case url
        case sha256
        case sizeBytes
    }
}

public struct ModelLicense: Codable, Equatable {
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

public struct ModelProvenance: Codable, Equatable {
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

public struct RuntimeParameters: Codable, Equatable {
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

public struct HallucinationThresholds: Codable, Equatable {
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
    static func validate(decoder: Decoder, allowedKeys: [String]) throws {
        let object = try [String: JSONValue](from: decoder)
        let observed = Set(object.keys)
        let allowed = Set(allowedKeys)
        let unknown = observed.subtracting(allowed).sorted()
        let missing = allowed.subtracting(observed).sorted()

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
