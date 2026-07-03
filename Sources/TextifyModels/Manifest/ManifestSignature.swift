import Foundation

public struct ManifestSignature: Codable, Equatable, Sendable {
    public let signatureVersion: Int
    public let keyId: String
    public let algorithm: String
    public let signatureBase64: String

    public static func decode(_ data: Data) throws -> ManifestSignature {
        try JSONDecoder().decode(ManifestSignature.self, from: data)
    }

    public init(
        signatureVersion: Int,
        keyId: String,
        algorithm: String,
        signatureBase64: String
    ) {
        self.signatureVersion = signatureVersion
        self.keyId = keyId
        self.algorithm = algorithm
        self.signatureBase64 = signatureBase64
    }

    public init(from decoder: Decoder) throws {
        try StrictJSONKeys.validate(
            decoder: decoder,
            allowedKeys: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        signatureVersion = try container.decode(Int.self, forKey: .signatureVersion)
        keyId = try container.decode(String.self, forKey: .keyId)
        algorithm = try container.decode(String.self, forKey: .algorithm)
        signatureBase64 = try container.decode(String.self, forKey: .signatureBase64)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case signatureVersion
        case keyId
        case algorithm
        case signatureBase64
    }
}
