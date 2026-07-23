import Foundation

public struct CatalogRatingPolicy: Codable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public let suiteID: String
    public let language: String
    public let quality: CatalogQualityPolicy
    public let speed: CatalogSpeedPolicy
    public let levels: [CatalogRatingLevelPolicy]

    public static func decode(_ data: Data) throws -> CatalogRatingPolicy {
        try validateCatalogRatingPolicyJSON(data)
        let policy = try JSONDecoder().decode(CatalogRatingPolicy.self, from: data)
        try policy.validate()
        return policy
    }

    public func level(for score: Int) -> CatalogRatingLevelPolicy {
        levels.first(where: { score >= $0.minimumScore }) ?? levels[levels.count - 1]
    }

    private func validate() throws {
        guard schemaVersion == 1 else {
            throw CatalogRatingPolicyError.unsupportedSchemaVersion(schemaVersion)
        }
        guard !id.isEmpty, !suiteID.isEmpty else {
            throw CatalogRatingPolicyError.invalidIdentity
        }
        guard language == "en" else {
            throw CatalogRatingPolicyError.unsupportedLanguage(language)
        }
        guard quality.components.count == 3 else {
            throw CatalogRatingPolicyError.invalidQualityComponents
        }
        let componentIDs = Set(quality.components.map(\.id))
        guard componentIDs.count == quality.components.count,
              !componentIDs.contains(quality.noSpeechComponentID),
              abs(quality.components.reduce(0) { $0 + $1.weight } - 1) < 0.000_001,
              quality.components.allSatisfy({
                  !$0.id.isEmpty
                      && $0.weight > 0
                      && $0.excellentWordErrorRate >= 0
                      && $0.unacceptableWordErrorRate > $0.excellentWordErrorRate
              })
        else {
            throw CatalogRatingPolicyError.invalidQualityComponents
        }
        let validNoSpeechCaps = quality.noSpeechCaps.isEmpty
            || (
                quality.noSpeechCaps.count == 4
                    && quality.noSpeechCaps.map(\.aboveFalsePositiveRate)
                        == quality.noSpeechCaps.map(\.aboveFalsePositiveRate).sorted(by: >)
                    && quality.noSpeechCaps.allSatisfy({
                        (0 ... 1).contains($0.aboveFalsePositiveRate)
                            && (1 ... 4).contains($0.maximumLevel)
                    })
            )
        guard !quality.noSpeechComponentID.isEmpty, validNoSpeechCaps
        else {
            throw CatalogRatingPolicyError.invalidNoSpeechCaps
        }
        guard !speed.referenceChip.isEmpty,
              speed.requiredFeedMode == "accelerated",
              speed.requiredRuns >= 3,
              speed.maximumRelativeP95Spread > 0,
              speed.maximumRelativeP95Spread < 1,
              speed.releaseToFinalWeight > 0,
              speed.realTimeFactorWeight > 0,
              abs(speed.releaseToFinalWeight + speed.realTimeFactorWeight - 1) < 0.000_001,
              speed.excellentP95ReleaseToFinalMs > 0,
              speed.unacceptableP95ReleaseToFinalMs > speed.excellentP95ReleaseToFinalMs,
              speed.excellentP95RealTimeFactor > 0,
              speed.unacceptableP95RealTimeFactor > speed.excellentP95RealTimeFactor
        else {
            throw CatalogRatingPolicyError.invalidSpeedPolicy
        }
        guard levels.map(\.level) == [5, 4, 3, 2, 1],
              levels.map(\.minimumScore) == levels.map(\.minimumScore).sorted(by: >),
              levels.last?.minimumScore == 0,
              levels.allSatisfy({
                  (0 ... 100).contains($0.minimumScore)
                      && !$0.qualityLabel.isEmpty
                      && !$0.speedLabel.isEmpty
              })
        else {
            throw CatalogRatingPolicyError.invalidLevels
        }
    }
}

public struct CatalogQualityPolicy: Codable, Sendable {
    public let components: [CatalogQualityComponentPolicy]
    public let noSpeechComponentID: String
    public let noSpeechCaps: [CatalogNoSpeechCapPolicy]
}

public struct CatalogQualityComponentPolicy: Codable, Sendable {
    public let id: String
    public let weight: Double
    public let excellentWordErrorRate: Double
    public let unacceptableWordErrorRate: Double
}

public struct CatalogNoSpeechCapPolicy: Codable, Sendable {
    public let aboveFalsePositiveRate: Double
    public let maximumLevel: Int
}

public struct CatalogSpeedPolicy: Codable, Sendable {
    public let referenceChip: String
    public let requiredFeedMode: String
    public let requiredRuns: Int
    public let maximumRelativeP95Spread: Double
    public let releaseToFinalWeight: Double
    public let realTimeFactorWeight: Double
    public let excellentP95ReleaseToFinalMs: Int
    public let unacceptableP95ReleaseToFinalMs: Int
    public let excellentP95RealTimeFactor: Double
    public let unacceptableP95RealTimeFactor: Double
}

public struct CatalogRatingLevelPolicy: Codable, Sendable {
    public let level: Int
    public let minimumScore: Int
    public let qualityLabel: String
    public let speedLabel: String
}

public enum CatalogRatingPolicyError: Error, Equatable, CustomStringConvertible {
    case unsupportedSchemaVersion(Int)
    case invalidIdentity
    case unsupportedLanguage(String)
    case invalidQualityComponents
    case invalidNoSpeechCaps
    case invalidSpeedPolicy
    case invalidLevels
    case invalidSchemaFields

    public var description: String {
        switch self {
        case let .unsupportedSchemaVersion(version):
            return "Unsupported catalog rating policy schema: \(version)"
        case .invalidIdentity:
            return "Catalog rating policy and suite ids must be non-empty."
        case let .unsupportedLanguage(language):
            return "Catalog rating policy must be English, received: \(language)"
        case .invalidQualityComponents:
            return "Catalog rating quality components or weights are invalid."
        case .invalidNoSpeechCaps:
            return "Catalog rating no-speech caps are invalid."
        case .invalidSpeedPolicy:
            return "Catalog rating speed policy is invalid."
        case .invalidLevels:
            return "Catalog rating levels are invalid."
        case .invalidSchemaFields:
            return "Catalog rating policy has missing or unknown fields."
        }
    }
}

private func validateCatalogRatingPolicyJSON(_ data: Data) throws {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          hasExactKeys(
              root,
              [
                  "schemaVersion", "id", "suiteID", "language", "quality", "speed",
                  "levels",
              ]
          )
    else {
        throw CatalogRatingPolicyError.invalidSchemaFields
    }
    guard let quality = root["quality"] as? [String: Any],
          hasExactKeys(quality, ["components", "noSpeechComponentID", "noSpeechCaps"]),
          let components = quality["components"] as? [[String: Any]],
          let noSpeechCaps = quality["noSpeechCaps"] as? [[String: Any]]
    else {
        throw CatalogRatingPolicyError.invalidSchemaFields
    }
    let validComponents = components.allSatisfy { component in
        hasExactKeys(
            component,
            [
                "id", "weight", "excellentWordErrorRate",
                "unacceptableWordErrorRate",
            ]
        )
    }
    let validCaps = noSpeechCaps.allSatisfy { cap in
        hasExactKeys(cap, ["aboveFalsePositiveRate", "maximumLevel"])
    }
    guard validComponents, validCaps,
          let speed = root["speed"] as? [String: Any],
          hasExactKeys(
              speed,
              [
                  "referenceChip", "requiredFeedMode", "requiredRuns",
                  "maximumRelativeP95Spread", "releaseToFinalWeight",
                  "realTimeFactorWeight", "excellentP95ReleaseToFinalMs",
                  "unacceptableP95ReleaseToFinalMs", "excellentP95RealTimeFactor",
                  "unacceptableP95RealTimeFactor",
              ]
          ),
          let levels = root["levels"] as? [[String: Any]]
    else {
        throw CatalogRatingPolicyError.invalidSchemaFields
    }
    guard levels.allSatisfy({ level in
        hasExactKeys(
            level,
            ["level", "minimumScore", "qualityLabel", "speedLabel"]
        )
    }) else {
        throw CatalogRatingPolicyError.invalidSchemaFields
    }
}

private func hasExactKeys(_ object: [String: Any], _ keys: Set<String>) -> Bool {
    Set(object.keys) == keys
}
