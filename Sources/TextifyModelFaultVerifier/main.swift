import Foundation
import TextifyReleaseVerification

@main
enum TextifyModelFaultVerifier {
    static func main() async throws {
        let arguments = CommandLine.arguments
        if arguments.dropFirst().first == "--fault-worker" {
            try await ModelProductionFaultWorker.run(
                arguments: Array(arguments.dropFirst())
            )
            return
        }
        guard arguments.count == 2 else {
            FileHandle.standardError.write(
                Data("usage: TextifyModelFaultVerifier <evidence-output.json>\n".utf8)
            )
            throw Exit.invalidArguments
        }

        let service = DeterministicModelDownloadService(
            payload: Data(repeating: 0x5a, count: 512 * 1_024)
        )
        try await service.start()
        let downloadReport: DeterministicModelDownloadReport
        do {
            downloadReport = try await service.exercise()
        } catch {
            service.stop()
            throw error
        }
        service.stop()

        let productionCampaign = try ModelProductionFaultCampaign().run(
            workerExecutableURL: URL(
                fileURLWithPath: arguments[0]
            ),
            repositoryRoot: URL(
                fileURLWithPath: FileManager.default.currentDirectoryPath,
                isDirectory: true
            )
        )
        let campaign = try ModelWorkflowFaultCampaign(seed: 24).run(
            operationCount: 1_000
        )
        let evidence = ModelFaultVerifierEvidence(
            schemaVersion: 2,
            campaign: campaign,
            productionCampaign: productionCampaign,
            downloadService: downloadReport
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes
        ]
        let data = try encoder.encode(evidence)
        try data.write(
            to: URL(fileURLWithPath: arguments[1]),
            options: .atomic
        )
    }
}

private struct ModelFaultVerifierEvidence: Codable {
    let schemaVersion: Int
    let campaign: ModelWorkflowFaultCampaignReport
    let productionCampaign: ModelProductionFaultCampaignReport
    let downloadService: DeterministicModelDownloadReport
}

private enum Exit: Error {
    case invalidArguments
}
