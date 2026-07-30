import Foundation
import TextifyModels

@main
enum TextifyModelRevocationVerifier {
    static func main() {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            guard arguments.count == 2 else {
                throw VerificationFailure(
                    "usage: TextifyModelRevocationVerifier "
                        + "<revocations.json> <revocations.json.sig>"
                )
            }

            let revocationData = try Data(
                contentsOf: URL(fileURLWithPath: arguments[0])
            )
            let signatureData = try Data(
                contentsOf: URL(fileURLWithPath: arguments[1])
            )
            let signature = try ModelRevocationSignature.decode(signatureData)
            if let expectedKeyID = ProcessInfo.processInfo.environment[
                "TEXTIFY_MODEL_REVOCATION_KEY_ID"
            ], signature.keyId != expectedKeyID {
                throw VerificationFailure(
                    "signature keyId \(signature.keyId) does not match "
                        + "expected keyId \(expectedKeyID)"
                )
            }
            guard ProductionModelCatalogTrust.trustedKeyIDs.contains(
                signature.keyId
            ) else {
                throw VerificationFailure(
                    "signature keyId \(signature.keyId) is not trusted"
                )
            }

            let snapshot = try TrustedModelRevocationSnapshot(
                revocationData: revocationData,
                signatureData: signatureData,
                verifier: ModelRevocationVerifier(
                    trustedKeys: ProductionModelCatalogTrust.trustedKeys
                )
            )
            print(
                "Verified signed model revocations revision "
                    + "\(snapshot.revision) with "
                    + "\(snapshot.envelope.records.count) records and "
                    + "\(snapshot.envelope.restorations.count) restorations"
            )
        } catch {
            FileHandle.standardError.write(
                Data("Revocation verification failed: \(error)\n".utf8)
            )
            Foundation.exit(1)
        }
    }
}

private struct VerificationFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
