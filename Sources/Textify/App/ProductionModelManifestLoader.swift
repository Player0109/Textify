import Foundation
import TextifyModels

struct ProductionModelManifestLoader {
    static let bundledDirectoryName = "ModelCatalog"
    static let bundledManifestName = "manifest.json"
    static let bundledSignatureName = "manifest.json.sig"

    let configuration: ProductionModelInstallConfiguration
    let resourceDirectory: URL?
    let transport: any DownloadTransport

    init(
        configuration: ProductionModelInstallConfiguration,
        resourceDirectory: URL? = Bundle.main.resourceURL,
        transport: any DownloadTransport = URLSessionDownloadTransport()
    ) {
        self.configuration = configuration
        self.resourceDirectory = resourceDirectory
        self.transport = transport
    }

    func load() async throws -> ModelManifest {
        let bundled = try loadBundledSnapshot()?.manifest

        do {
            let remote = try await downloadRemoteSnapshot().manifest
            guard let bundled else {
                return remote
            }
            return try Self.newest(bundled: bundled, remote: remote)
        } catch {
            guard let bundled else {
                throw error
            }
            return bundled
        }
    }

    func downloadRemoteSnapshot() async throws -> TrustedCatalogSnapshot {
        try await ModelDownloader(
            transport: transport,
            manifestVerifier: verifier
        ).downloadManifestSnapshot(
            manifestURL: configuration.manifestURL,
            signatureURL: configuration.signatureURL
        )
    }

    func downloadRemoteRevocationSnapshot() async throws
        -> TrustedModelRevocationSnapshot {
        guard let revocationURL = configuration.revocationURL,
              let signatureURL = configuration.revocationSignatureURL
        else {
            throw ModelCatalogRefreshError.unavailable
        }
        return try await ModelRevocationDownloader(
            transport: transport,
            verifier: ModelRevocationVerifier(
                trustedKeys: configuration.trustedKeys
            )
        ).downloadSnapshot(
            revocationURL: revocationURL,
            signatureURL: signatureURL
        )
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

    static func newest(
        bundled: ModelManifest,
        remote: ModelManifest
    ) throws -> ModelManifest {
        let formatter = ISO8601DateFormatter()
        guard let bundledDate = formatter.date(from: bundled.generatedAt) else {
            throw ProductionModelPolicyError.invalidGeneratedAt(bundled.generatedAt)
        }
        guard let remoteDate = formatter.date(from: remote.generatedAt) else {
            throw ProductionModelPolicyError.invalidGeneratedAt(remote.generatedAt)
        }
        return remoteDate >= bundledDate ? remote : bundled
    }

    private var verifier: ManifestVerifier {
        ManifestVerifier(
            trustedKeys: configuration.trustedKeys,
            legacyPolicy: .publishedV1_1
        )
    }
}
