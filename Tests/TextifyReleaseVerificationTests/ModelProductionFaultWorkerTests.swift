import Foundation
import TextifyModels
@testable import TextifyReleaseVerification
import XCTest

final class ModelProductionFaultWorkerTests: XCTestCase {
    func testSoakAuditRejectsInstalledPayloadWithoutReceipt() async throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "TextifyProductionSoakAudit-\(UUID().uuidString)",
                isDirectory: true
            )
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = ModelStorageLayout(
            rootDirectory: root.appendingPathComponent(
                "Models",
                isDirectory: true
            )
        )
        let installedURL = try layout.installedFileURL(
            modelID: ProductionModelPolicy.requiredModelID,
            filename: "model.bin"
        )
        try FileManager.default.createDirectory(
            at: installedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Tests/TextifyModelsTests/Fixtures/Models/model.bin"
            )
        ).write(to: installedURL)

        try await ModelProductionSoakWorker(
            root: root,
            repositoryRoot: repositoryRoot,
            seed: 24
        ).recover(expectedOperationCount: 0)

        let result = try JSONDecoder().decode(
            ModelProductionSoakRecoveryResult.self,
            from: Data(
                contentsOf: root.appendingPathComponent(
                    "soak-recovery.json"
                )
            )
        )
        XCTAssertTrue(
            result.invariantViolations.contains(
                "soak_installed_payload_without_receipt"
            )
        )
        XCTAssertEqual(result.unexplainedManagedBytes, 33)
    }

    func testEveryShippingBoundaryRecoversAfterInjectedPersistenceFailure() async throws {
        let repositoryRoot = URL(
            fileURLWithPath: #filePath
        )
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

        for boundary in ModelWorkflowDurableBoundary.allCases {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent(
                    "TextifyProductionWorker-\(UUID().uuidString)",
                    isDirectory: true
                )
            defer { try? FileManager.default.removeItem(at: root) }
            try await ModelProductionFaultWorker.run(arguments: [
                "--fault-worker",
                "perform",
                root.path,
                boundary.rawValue,
                ModelWorkflowInjectedFault.diskFull.rawValue,
                repositoryRoot.path,
            ])
            try await ModelProductionFaultWorker.run(arguments: [
                "--fault-worker",
                "recover",
                root.path,
                boundary.rawValue,
                ModelWorkflowInjectedFault.diskFull.rawValue,
                repositoryRoot.path,
            ])
            let object = try XCTUnwrap(
                try JSONSerialization.jsonObject(
                    with: Data(
                        contentsOf: root.appendingPathComponent(
                            "recovery-result.json"
                        )
                    )
                ) as? [String: Any]
            )

            XCTAssertEqual(
                object["failpointReached"] as? Bool,
                true,
                boundary.rawValue
            )
            XCTAssertEqual(
                object["invariantViolations"] as? [String],
                [],
                boundary.rawValue
            )
            XCTAssertEqual(
                object["unexplainedManagedBytes"] as? Int,
                0,
                boundary.rawValue
            )
        }
    }
}
