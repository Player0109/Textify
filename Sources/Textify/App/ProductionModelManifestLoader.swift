import Foundation
import TextifyModels

struct ProductionModelManifestLoader {
    static let bundledDirectoryName = "ModelCatalog"
    static let bundledManifestName = "manifest.json"
    static let bundledSignatureName = "manifest.json.sig"

    let configuration: ProductionModelInstallConfiguration
    let resourceDirectory: URL?

    init(
        configuration: ProductionModelInstallConfiguration,
        resourceDirectory: URL? = Bundle.main.resourceURL
    ) {
        self.configuration = configuration
        self.resourceDirectory = resourceDirectory
    }

    func load() async throws -> ModelManifest {
        let verifier = ManifestVerifier(
            trustedKeys: configuration.trustedKeys,
            legacyPolicy: .publishedV1_1
        )
        let bundled = try loadBundledManifest(verifier: verifier)

        do {
            let remote = try await ModelDownloader(
                manifestVerifier: verifier
            ).downloadManifest(
                manifestURL: configuration.manifestURL,
                signatureURL: configuration.signatureURL
            )
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

    private func loadBundledManifest(verifier: ManifestVerifier) throws -> ModelManifest? {
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
        let manifest = try verifier.verify(
            manifestData: Data(contentsOf: manifestURL),
            signatureData: Data(contentsOf: signatureURL)
        )
        try ProductionModelPolicy.validateProductionManifest(manifest)
        return manifest
    }
}
