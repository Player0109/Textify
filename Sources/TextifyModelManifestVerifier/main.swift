import Darwin
import Foundation
import TextifyModels

private enum CommandError: Error, CustomStringConvertible {
    case invalidArguments
    case missingPublicKey
    case invalidSignatureEnvelope
    case unexpectedKeyID(expected: String, actual: String)

    var description: String {
        switch self {
        case .invalidArguments:
            return "usage: TextifyModelManifestVerifier <manifest.json> <manifest.json.sig>"
        case .missingPublicKey:
            return "TEXTIFY_MODEL_MANIFEST_PUBLIC_KEY_BASE64 is required"
        case .invalidSignatureEnvelope:
            return "signature envelope must contain a non-empty keyId"
        case let .unexpectedKeyID(expected, actual):
            return "signature keyId \(actual) does not match expected keyId \(expected)"
        }
    }
}

private func fail(_ error: Error) -> Never {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}

do {
    guard CommandLine.arguments.count == 3 else {
        throw CommandError.invalidArguments
    }

    let environment = ProcessInfo.processInfo.environment
    guard let publicKey = environment[
        "TEXTIFY_MODEL_MANIFEST_PUBLIC_KEY_BASE64"
    ], !publicKey.isEmpty else {
        throw CommandError.missingPublicKey
    }

    let manifestURL = URL(fileURLWithPath: CommandLine.arguments[1])
    let signatureURL = URL(fileURLWithPath: CommandLine.arguments[2])
    let manifestData = try Data(contentsOf: manifestURL)
    let signatureData = try Data(contentsOf: signatureURL)
    guard let signatureObject = try JSONSerialization.jsonObject(
        with: signatureData
    ) as? [String: Any],
          let keyID = signatureObject["keyId"] as? String,
          !keyID.isEmpty
    else {
        throw CommandError.invalidSignatureEnvelope
    }

    if let expectedKeyID = environment["TEXTIFY_MODEL_MANIFEST_KEY_ID"],
       !expectedKeyID.isEmpty,
       expectedKeyID != keyID {
        throw CommandError.unexpectedKeyID(
            expected: expectedKeyID,
            actual: keyID
        )
    }

    let verifier = ManifestVerifier(
        trustedKeys: [
            TrustedModelManifestKey(
                keyId: keyID,
                publicKeyBase64: publicKey
            )
        ],
        legacyPolicy: .publishedV1_1
    )
    let manifest = try verifier.verify(
        manifestData: manifestData,
        signatureData: signatureData
    )
    try ProductionModelPolicy.validateProductionManifest(manifest)

    print(
        "Verified \(manifestURL.path) with \(manifest.models.count) model(s) "
            + "and keyId \(keyID)"
    )
} catch {
    fail(error)
}
