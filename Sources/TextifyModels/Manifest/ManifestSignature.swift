import Foundation

public struct ManifestSignature: Codable, Equatable, Sendable {
    public let signatureVersion: Int
    public let keyId: String
    public let algorithm: String
    public let signatureBase64: String

    public static func decode(_ data: Data) throws -> ManifestSignature {
        try JSONDecoder().decode(ManifestSignature.self, from: data)
    }
}
