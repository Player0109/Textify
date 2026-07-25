import Darwin
import Foundation
import TextifyModels

private enum CommandError: Error, CustomStringConvertible {
    case invalidArguments
    case unexpectedBundleIdentifier(String)

    var description: String {
        switch self {
        case .invalidArguments:
            """
            usage: TextifyCatalogPublicationVerifier \
            [--bootstrap] \
            <manifest.json> <manifest.json.sig> \
            <revocations.json> <revocations.json.sig> \
            <candidate.app> <evidence.json> <previous-evidence.json>

            --bootstrap is allowed only for the first v3 authority baseline
            and omits <previous-evidence.json>.
            """
        case let .unexpectedBundleIdentifier(identifier):
            "unexpected candidate bundle identifier: \(identifier)"
        }
    }
}

private func fail(_ error: Error) -> Never {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}

do {
    var arguments = Array(CommandLine.arguments.dropFirst())
    let isBootstrap = arguments.first == "--bootstrap"
    if isBootstrap {
        arguments.removeFirst()
    }
    guard arguments.count == (isBootstrap ? 6 : 7) else {
        throw CommandError.invalidArguments
    }
    let environment = ProcessInfo.processInfo.environment
    let catalogVerifier = ManifestVerifier(
        trustedKeys: ProductionModelCatalogTrust.trustedKeys
    )
    let revocationVerifier = ModelRevocationVerifier(
        trustedKeys: ProductionModelCatalogTrust.trustedKeys
    )
    let catalog = try TrustedCatalogSnapshot(
        manifestData: Data(
            contentsOf: URL(
                fileURLWithPath: arguments[0]
            )
        ),
        signatureData: Data(
            contentsOf: URL(
                fileURLWithPath: arguments[1]
            )
        ),
        verifier: catalogVerifier
    )
    let revocations = try TrustedModelRevocationSnapshot(
        revocationData: Data(
            contentsOf: URL(
                fileURLWithPath: arguments[2]
            )
        ),
        signatureData: Data(
            contentsOf: URL(
                fileURLWithPath: arguments[3]
            )
        ),
        verifier: revocationVerifier
    )
    let previousEvidence: ModelCatalogPublicationEvidence?
    if isBootstrap {
        previousEvidence = nil
    } else {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        previousEvidence = try decoder.decode(
            ModelCatalogPublicationEvidence.self,
            from: Data(
                contentsOf: URL(
                    fileURLWithPath: arguments[6]
                )
            )
        )
    }
    let appBundleURL = URL(
        fileURLWithPath: arguments[4],
        isDirectory: true
    )
    let buildIdentity = try ModelCatalogBuildIdentity.loadVerified(
        fromAppBundle: appBundleURL
    )
    guard buildIdentity.bundleIdentifier
            == ProductionModelCatalogTrust.bundleIdentifier
    else {
        throw CommandError.unexpectedBundleIdentifier(
            buildIdentity.bundleIdentifier
        )
    }
    let evidence = try ModelCatalogPublicationPolicy.validate(
        catalog: catalog,
        revocations: revocations,
        allowedCatalogSignerKeyIDs:
            ProductionModelCatalogTrust.trustedKeyIDs,
        allowedRevocationSignerKeyIDs:
            ProductionModelCatalogTrust.trustedKeyIDs,
        buildIdentity: buildIdentity,
        previousEvidence: previousEvidence,
        sourceEndpoint:
            environment["TEXTIFY_CATALOG_SOURCE_ENDPOINT"]
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let evidenceURL = URL(
        fileURLWithPath: arguments[5]
    )
    try FileManager.default.createDirectory(
        at: evidenceURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try encoder.encode(evidence).write(
        to: evidenceURL,
        options: .atomic
    )
    print(
        "Verified catalog \(evidence.catalogRevision) "
            + "(\(evidence.catalogSignerKeyID)), revocations "
            + "\(evidence.revocationRevision) "
            + "(\(evidence.revocationSignerKeyID)), and build "
            + evidence.buildIdentity.description
    )
} catch {
    fail(error)
}
