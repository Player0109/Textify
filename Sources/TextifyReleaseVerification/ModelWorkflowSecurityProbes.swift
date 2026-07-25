import Foundation
import TextifyDiagnostics
import TextifyModels

struct ModelWorkflowSecurityProbeRunner {
    func run() -> [ModelWorkflowSecurityProbeResult] {
        ModelWorkflowSecurityProbe.allCases.map {
            ModelWorkflowSecurityProbeResult(
                probe: $0,
                passed: run($0)
            )
        }
    }

    private func run(_ probe: ModelWorkflowSecurityProbe) -> Bool {
        switch probe {
        case .traversal:
            traversalIsRejected()
        case .symbolicLinkEscape:
            symbolicLinkEscapeIsRejected()
        case .hardLinkEscape:
            hardLinkedEvidenceIsRejected()
        case .archiveExpansionLimits:
            unsupportedArchiveExpansionIsRejected()
        case .peakStorageAdmission:
            peakStorageAdmissionIsEnforced()
        case .canonicalDigestAliasing:
            digestAliasesRequireExactIdentity()
        case .unsafeHelpURL:
            unsafeHelpURLsAreRejected()
        case .atomicFilesystemContainment:
            atomicDestinationIsContained()
        }
    }

    private func unsupportedArchiveExpansionIsRejected() -> Bool {
        let unsupportedLayoutsAreRejected =
            ["archive", "zip", "tar"].allSatisfy { layout in
            (try? JSONDecoder().decode(
                ModelArtifactLayout.self,
                from: Data("\"\(layout)\"".utf8)
            )) == nil
        }
        let policy = ModelInstallationExpansionPolicy(
            maximumEntryCount: 2,
            maximumExpandedBytes: 10,
            maximumPathDepth: 2
        )
        let entryCountRejected = throwsError {
            try policy.validate([
                .init(relativePath: "a", expandedBytes: 1),
                .init(relativePath: "b", expandedBytes: 1),
                .init(relativePath: "c", expandedBytes: 1),
            ])
        }
        let expandedSizeRejected = throwsError {
            try policy.validate([
                .init(relativePath: "model.bin", expandedBytes: 11),
            ])
        }
        let pathDepthRejected = throwsError {
            try policy.validate([
                .init(relativePath: "a/b/c", expandedBytes: 1),
            ])
        }
        return unsupportedLayoutsAreRejected
            && entryCountRejected
            && expandedSizeRejected
            && pathDepthRejected
    }

    private func throwsError(_ operation: () throws -> Void) -> Bool {
        do {
            try operation()
            return false
        } catch {
            return true
        }
    }

    private func traversalIsRejected() -> Bool {
        let layout = ModelStorageLayout(
            rootDirectory: URL(fileURLWithPath: "/tmp/Textify/Models")
        )
        return (try? layout.installedArtifactURL(
            modelID: "../escape",
            relativePath: "model.bin"
        )) == nil
    }

    private func symbolicLinkEscapeIsRejected() -> Bool {
        withTemporaryRoots { managedRoot, externalRoot in
            let layout = ModelStorageLayout(rootDirectory: managedRoot)
            try FileManager.default.createDirectory(
                at: layout.installedModelsDirectory,
                withIntermediateDirectories: true
            )
            let linkedModel = layout.installedModelsDirectory
                .appendingPathComponent("linked-model")
            try FileManager.default.createSymbolicLink(
                at: linkedModel,
                withDestinationURL: externalRoot
            )
            return (try? layout.installedFileURL(
                modelID: "linked-model",
                filename: "model.bin"
            )) == nil
        }
    }

    private func hardLinkedEvidenceIsRejected() -> Bool {
        withTemporaryRoots { managedRoot, externalRoot in
            let outside = externalRoot.appendingPathComponent("outside.bin")
            let inside = managedRoot.appendingPathComponent("inside.bin")
            try Data("outside".utf8).write(to: outside)
            try FileManager.default.createDirectory(
                at: managedRoot,
                withIntermediateDirectories: true
            )
            try FileManager.default.linkItem(at: outside, to: inside)
            return !ReleaseEvidenceFilePolicy.accepts(
                inside,
                in: managedRoot
            )
        }
    }

    private func peakStorageAdmissionIsEnforced() -> Bool {
        let requirement = ModelStorageAdmissionRequirement(
            completeTransferBytes: 1_000,
            finalArtifactBytes: 2_000,
            peakInstallationBytes: 4_000
        )
        let required = requirement.requiredAdditionalCapacity(
            reusable: .none
        )
        guard (try? requirement.requireCapacity(
            availableBytes: required,
            reusable: .none
        )) != nil else {
            return false
        }
        do {
            try requirement.requireCapacity(
                availableBytes: required - 1,
                reusable: .none
            )
            return false
        } catch {
            return true
        }
    }

    private func digestAliasesRequireExactIdentity() -> Bool {
        let matching = ModelArtifactTypedDigest(
            type: .singleFileSHA256,
            value: String(repeating: "a", count: 64)
        )
        let different = ModelArtifactTypedDigest(
            type: .singleFileSHA256,
            value: String(repeating: "b", count: 64)
        )
        return ProductionModelPolicy.artifactAliasDigestsMatch(
            aliasDigests: [matching],
            canonicalDigests: [matching]
        ) && !ProductionModelPolicy.artifactAliasDigestsMatch(
            aliasDigests: [matching],
            canonicalDigests: [different]
        )
    }

    private func unsafeHelpURLsAreRejected() -> Bool {
        !ProductionModelPolicy.isApprovedHTTPSURL(
            "javascript:alert(1)"
        ) && !ProductionModelPolicy.isApprovedHTTPSURL(
            "https://user@example.com/help"
        ) && ProductionModelPolicy.isApprovedHTTPSURL(
            "https://github.com/Player0109/Textify"
        )
    }

    private func atomicDestinationIsContained() -> Bool {
        withTemporaryRoots { managedRoot, externalRoot in
            let layout = ModelStorageLayout(rootDirectory: managedRoot)
            try FileManager.default.createDirectory(
                at: layout.installedModelsDirectory,
                withIntermediateDirectories: true
            )
            let modelRoot = layout.installedModelsDirectory
                .appendingPathComponent("artifact")
            try FileManager.default.createSymbolicLink(
                at: modelRoot,
                withDestinationURL: externalRoot
            )
            return (try? layout.installedArtifactURL(
                modelID: "artifact",
                relativePath: "nested/model.bin"
            )) == nil
        }
    }

    private func withTemporaryRoots(
        _ body: (URL, URL) throws -> Bool
    ) -> Bool {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TextifySecurityProbe-\(UUID().uuidString)",
            isDirectory: true
        )
        let managedRoot = parent.appendingPathComponent(
            "managed",
            isDirectory: true
        )
        let externalRoot = parent.appendingPathComponent(
            "external",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: parent) }
        do {
            try FileManager.default.createDirectory(
                at: externalRoot,
                withIntermediateDirectories: true
            )
            return try body(managedRoot, externalRoot)
        } catch {
            return false
        }
    }
}

enum ModelCatalogPrivacyProbe {
    static func catalogRequests() -> [ModelCatalogRequestEvidence] {
        [
            "/models/manifest.json",
            "/models/manifest.json.sig",
            "/models/revocations.json",
            "/models/revocations.json.sig"
        ].compactMap {
            guard let url = URL(string: "https://example.com\($0)") else {
                return nil
            }
            let request = ModelDownloadURLPolicy.anonymousGET(url)
            return ModelCatalogRequestEvidence(
                method: request.httpMethod ?? "",
                path: url.path,
                query: url.query,
                bodyBytes: request.httpBody?.count ?? 0,
                localIdentityHeaders:
                    request.allHTTPHeaderFields?.keys.sorted() ?? []
            )
        }
    }

    static func diagnosticsEvidence() -> ModelDiagnosticsPrivacyEvidence {
        let fullHash = String(repeating: "a", count: 64)
        let input = #"{"event":"model_load","modelID":"\#(fullHash)"}"#
        let output = DiagnosticsRedactor().redactLogContents(input)
        return ModelDiagnosticsPrivacyEvidence(
            containsFullSHA256: output.contains(fullHash)
        )
    }
}
