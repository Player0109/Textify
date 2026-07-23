import Foundation

public struct ModelBenchmarkRating: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let policyID: String
    public let suiteID: String
    public let suiteIndexSHA256: String
    public let modelID: String
    public let engine: String
    public let engineVersion: String
    public let modelLicense: String
    public let computeBackend: String
    public let artifactFingerprint: String
    public let sourceRevision: String
    public let language: String
    public let measuredAt: String
    public let referenceHost: ModelBenchmarkHost
    public let runCount: Int
    public let quality: ModelBenchmarkQualityRating
    public let speed: ModelBenchmarkSpeedRating?
    public let speedUnratedReason: String?

    public init(
        schemaVersion: Int,
        policyID: String,
        suiteID: String,
        suiteIndexSHA256: String,
        modelID: String,
        engine: String,
        engineVersion: String,
        modelLicense: String,
        computeBackend: String,
        artifactFingerprint: String,
        sourceRevision: String,
        language: String,
        measuredAt: String,
        referenceHost: ModelBenchmarkHost,
        runCount: Int,
        quality: ModelBenchmarkQualityRating,
        speed: ModelBenchmarkSpeedRating?,
        speedUnratedReason: String?
    ) {
        self.schemaVersion = schemaVersion
        self.policyID = policyID
        self.suiteID = suiteID
        self.suiteIndexSHA256 = suiteIndexSHA256
        self.modelID = modelID
        self.engine = engine
        self.engineVersion = engineVersion
        self.modelLicense = modelLicense
        self.computeBackend = computeBackend
        self.artifactFingerprint = artifactFingerprint
        self.sourceRevision = sourceRevision
        self.language = language
        self.measuredAt = measuredAt
        self.referenceHost = referenceHost
        self.runCount = runCount
        self.quality = quality
        self.speed = speed
        self.speedUnratedReason = speedUnratedReason
    }

    public init(from decoder: Decoder) throws {
        try StrictJSONKeys.validate(
            decoder: decoder,
            allowedKeys: CodingKeys.allCases.map(\.stringValue),
            requiredKeys: CodingKeys.required.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        policyID = try container.decode(String.self, forKey: .policyID)
        suiteID = try container.decode(String.self, forKey: .suiteID)
        suiteIndexSHA256 = try container.decode(String.self, forKey: .suiteIndexSHA256)
        modelID = try container.decode(String.self, forKey: .modelID)
        engine = try container.decode(String.self, forKey: .engine)
        engineVersion = try container.decode(String.self, forKey: .engineVersion)
        modelLicense = try container.decode(String.self, forKey: .modelLicense)
        computeBackend = try container.decode(String.self, forKey: .computeBackend)
        artifactFingerprint = try container.decode(String.self, forKey: .artifactFingerprint)
        sourceRevision = try container.decode(String.self, forKey: .sourceRevision)
        language = try container.decode(String.self, forKey: .language)
        measuredAt = try container.decode(String.self, forKey: .measuredAt)
        referenceHost = try container.decode(ModelBenchmarkHost.self, forKey: .referenceHost)
        runCount = try container.decode(Int.self, forKey: .runCount)
        quality = try container.decode(ModelBenchmarkQualityRating.self, forKey: .quality)
        speed = try container.decodeIfPresent(ModelBenchmarkSpeedRating.self, forKey: .speed)
        speedUnratedReason = try container.decodeIfPresent(
            String.self,
            forKey: .speedUnratedReason
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case schemaVersion
        case policyID
        case suiteID
        case suiteIndexSHA256
        case modelID
        case engine
        case engineVersion
        case modelLicense
        case computeBackend
        case artifactFingerprint
        case sourceRevision
        case language
        case measuredAt
        case referenceHost
        case runCount
        case quality
        case speed
        case speedUnratedReason

        static let required: [CodingKeys] = [
            .schemaVersion,
            .policyID,
            .suiteID,
            .suiteIndexSHA256,
            .modelID,
            .engine,
            .engineVersion,
            .modelLicense,
            .computeBackend,
            .artifactFingerprint,
            .sourceRevision,
            .language,
            .measuredAt,
            .referenceHost,
            .runCount,
            .quality,
        ]
    }
}

public struct ModelBenchmarkHost: Codable, Equatable, Sendable {
    public let chip: String
    public let operatingSystem: String
    public let architecture: String

    public init(chip: String, operatingSystem: String, architecture: String) {
        self.chip = chip
        self.operatingSystem = operatingSystem
        self.architecture = architecture
    }

    public init(from decoder: Decoder) throws {
        try StrictJSONKeys.validate(
            decoder: decoder,
            allowedKeys: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        chip = try container.decode(String.self, forKey: .chip)
        operatingSystem = try container.decode(String.self, forKey: .operatingSystem)
        architecture = try container.decode(String.self, forKey: .architecture)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case chip
        case operatingSystem
        case architecture
    }
}

public struct ModelBenchmarkQualityRating: Codable, Equatable, Sendable {
    public let score: Int
    public let level: Int
    public let label: String
    public let speechItems: Int
    public let noSpeechItems: Int
    public let noSpeechFalsePositiveRate: Double
    public let components: [ModelBenchmarkQualityComponent]

    public init(
        score: Int,
        level: Int,
        label: String,
        speechItems: Int,
        noSpeechItems: Int,
        noSpeechFalsePositiveRate: Double,
        components: [ModelBenchmarkQualityComponent]
    ) {
        self.score = score
        self.level = level
        self.label = label
        self.speechItems = speechItems
        self.noSpeechItems = noSpeechItems
        self.noSpeechFalsePositiveRate = noSpeechFalsePositiveRate
        self.components = components
    }

    public init(from decoder: Decoder) throws {
        try StrictJSONKeys.validate(
            decoder: decoder,
            allowedKeys: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        score = try container.decode(Int.self, forKey: .score)
        level = try container.decode(Int.self, forKey: .level)
        label = try container.decode(String.self, forKey: .label)
        speechItems = try container.decode(Int.self, forKey: .speechItems)
        noSpeechItems = try container.decode(Int.self, forKey: .noSpeechItems)
        noSpeechFalsePositiveRate = try container.decode(
            Double.self,
            forKey: .noSpeechFalsePositiveRate
        )
        components = try container.decode(
            [ModelBenchmarkQualityComponent].self,
            forKey: .components
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case score
        case level
        case label
        case speechItems
        case noSpeechItems
        case noSpeechFalsePositiveRate
        case components
    }
}

public struct ModelBenchmarkQualityComponent: Codable, Equatable, Sendable {
    public let id: String
    public let wordErrorRate: Double
    public let score: Double
    public let weight: Double

    public init(id: String, wordErrorRate: Double, score: Double, weight: Double) {
        self.id = id
        self.wordErrorRate = wordErrorRate
        self.score = score
        self.weight = weight
    }

    public init(from decoder: Decoder) throws {
        try StrictJSONKeys.validate(
            decoder: decoder,
            allowedKeys: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        wordErrorRate = try container.decode(Double.self, forKey: .wordErrorRate)
        score = try container.decode(Double.self, forKey: .score)
        weight = try container.decode(Double.self, forKey: .weight)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case wordErrorRate
        case score
        case weight
    }
}

public struct ModelBenchmarkSpeedRating: Codable, Equatable, Sendable {
    public let score: Int
    public let level: Int
    public let label: String
    public let p50ReleaseToFinalMs: Int
    public let p95ReleaseToFinalMs: Int
    public let p95RealTimeFactor: Double
    public let relativeP95Spread: Double

    public init(
        score: Int,
        level: Int,
        label: String,
        p50ReleaseToFinalMs: Int,
        p95ReleaseToFinalMs: Int,
        p95RealTimeFactor: Double,
        relativeP95Spread: Double
    ) {
        self.score = score
        self.level = level
        self.label = label
        self.p50ReleaseToFinalMs = p50ReleaseToFinalMs
        self.p95ReleaseToFinalMs = p95ReleaseToFinalMs
        self.p95RealTimeFactor = p95RealTimeFactor
        self.relativeP95Spread = relativeP95Spread
    }

    public init(from decoder: Decoder) throws {
        try StrictJSONKeys.validate(
            decoder: decoder,
            allowedKeys: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        score = try container.decode(Int.self, forKey: .score)
        level = try container.decode(Int.self, forKey: .level)
        label = try container.decode(String.self, forKey: .label)
        p50ReleaseToFinalMs = try container.decode(Int.self, forKey: .p50ReleaseToFinalMs)
        p95ReleaseToFinalMs = try container.decode(Int.self, forKey: .p95ReleaseToFinalMs)
        p95RealTimeFactor = try container.decode(Double.self, forKey: .p95RealTimeFactor)
        relativeP95Spread = try container.decode(Double.self, forKey: .relativeP95Spread)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case score
        case level
        case label
        case p50ReleaseToFinalMs
        case p95ReleaseToFinalMs
        case p95RealTimeFactor
        case relativeP95Spread
    }
}
