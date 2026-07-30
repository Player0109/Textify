import Foundation
import TextifyModels

enum ProductionModelManifestLoaderError: Error, Equatable {
    case bundledCatalogMissing
    case bundledRevocationMissing
    case bundledRevocationIncomplete
}

struct ProductionBundledModelTrust {
    let catalogSnapshot: TrustedCatalogSnapshot
    let revocationState: TrustedModelRevocationState
}

struct ProductionModelManifestLoader {
    static let bundledDirectoryName = "ModelCatalog"
    static let bundledManifestName = "manifest.json"
    static let bundledSignatureName = "manifest.json.sig"
    static let bundledRevocationName = "revocations.json"
    static let bundledRevocationSignatureName = "revocations.json.sig"

    let configuration: ProductionModelInstallConfiguration
    let resourceDirectory: URL?

    init(
        configuration: ProductionModelInstallConfiguration,
        resourceDirectory: URL? = Bundle.main.resourceURL
    ) {
        self.configuration = configuration
        self.resourceDirectory = resourceDirectory
    }

    func loadBundledSnapshot() throws -> TrustedCatalogSnapshot? {
        guard let resourceDirectory else {
            return nil
        }
        let catalogDirectory = resourceDirectory.appendingPathComponent(
            Self.bundledDirectoryName,
            isDirectory: true
        )
        let manifestURL = catalogDirectory.appendingPathComponent(Self.bundledManifestName)
        let signatureURL = catalogDirectory.appendingPathComponent(Self.bundledSignatureName)
        let manifestExists = FileManager.default.fileExists(atPath: manifestURL.path)
        let signatureExists = FileManager.default.fileExists(atPath: signatureURL.path)

        guard manifestExists || signatureExists else {
            return nil
        }
        guard manifestExists, signatureExists else {
            throw ModelInstallCoordinatorError.bundledCatalogIncomplete
        }
        return try TrustedCatalogSnapshot(
            manifestData: Data(contentsOf: manifestURL),
            signatureData: Data(contentsOf: signatureURL),
            verifier: verifier
        )
    }

    func loadBundledRevocationSnapshot() throws
        -> TrustedModelRevocationSnapshot {
        guard let resourceDirectory else {
            throw ProductionModelManifestLoaderError
                .bundledRevocationMissing
        }
        let catalogDirectory = resourceDirectory.appendingPathComponent(
            Self.bundledDirectoryName,
            isDirectory: true
        )
        let revocationURL = catalogDirectory.appendingPathComponent(
            Self.bundledRevocationName
        )
        let signatureURL = catalogDirectory.appendingPathComponent(
            Self.bundledRevocationSignatureName
        )
        let revocationExists = FileManager.default.fileExists(
            atPath: revocationURL.path
        )
        let signatureExists = FileManager.default.fileExists(
            atPath: signatureURL.path
        )

        guard revocationExists || signatureExists else {
            throw ProductionModelManifestLoaderError
                .bundledRevocationMissing
        }
        guard revocationExists, signatureExists else {
            throw ProductionModelManifestLoaderError
                .bundledRevocationIncomplete
        }
        return try TrustedModelRevocationSnapshot(
            revocationData: Data(contentsOf: revocationURL),
            signatureData: Data(contentsOf: signatureURL),
            verifier: revocationVerifier
        )
    }

    func loadBundledTrust(
        persistedRevocationState: TrustedModelRevocationState,
        saveRevocationState:
            (TrustedModelRevocationState) throws -> Void
    ) throws -> ProductionBundledModelTrust {
        let revocationSnapshot = try loadBundledRevocationSnapshot()
        var revocationState = try persistedRevocationState.accepting(
            revocationSnapshot
        )
        guard let catalogSnapshot = try loadBundledSnapshot() else {
            throw ProductionModelManifestLoaderError.bundledCatalogMissing
        }
        revocationState = revocationState.retainingAliases(
            from: catalogSnapshot
        )
        if revocationState != persistedRevocationState {
            try saveRevocationState(revocationState)
        }
        return ProductionBundledModelTrust(
            catalogSnapshot: catalogSnapshot,
            revocationState: revocationState
        )
    }

    private var verifier: ManifestVerifier {
        ManifestVerifier(
            trustedKeys: configuration.trustedKeys,
            legacyPolicy: .publishedV1_1
        )
    }

    private var revocationVerifier: ModelRevocationVerifier {
        ModelRevocationVerifier(
            trustedKeys: configuration.trustedKeys
        )
    }
}
