import Foundation

public struct ManifestSignature: Codable, Equatable, Sendable {
    public let signatureVersion: Int
    public let signatureType: String
    public let algorithm: String
    public let keyId: String
    public let manifestFile: String
    public let contentType: String
    public let contentSHA256: String
    public let signature: String

    public static func decode(_ data: Data) throws -> ManifestSignature {
        try JSONDecoder().decode(ManifestSignature.self, from: data)
    }

    public init(
        signatureVersion: Int,
        signatureType: String,
        algorithm: String,
        keyId: String,
        manifestFile: String,
        contentType: String,
        contentSHA256: String,
        signature: String
    ) {
        self.signatureVersion = signatureVersion
        self.signatureType = signatureType
        self.algorithm = algorithm
        self.keyId = keyId
        self.manifestFile = manifestFile
        self.contentType = contentType
        self.contentSHA256 = contentSHA256
        self.signature = signature
    }

    public init(from decoder: Decoder) throws {
        try StrictJSONKeys.validate(
            decoder: decoder,
            allowedKeys: CodingKeys.allCases.map(\.stringValue)
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        signatureVersion = try container.decode(Int.self, forKey: .signatureVersion)
        signatureType = try container.decode(String.self, forKey: .signatureType)
        algorithm = try container.decode(String.self, forKey: .algorithm)
        keyId = try container.decode(String.self, forKey: .keyId)
        manifestFile = try container.decode(String.self, forKey: .manifestFile)
        contentType = try container.decode(String.self, forKey: .contentType)
        contentSHA256 = try container.decode(String.self, forKey: .contentSHA256)
        signature = try container.decode(String.self, forKey: .signature)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case signatureVersion
        case signatureType
        case algorithm
        case keyId
        case manifestFile
        case contentType
        case contentSHA256
        case signature
    }
}
