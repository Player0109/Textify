import Foundation
import TextifyReleaseVerification

@main
enum TextifyModelFaultVerifier {
    static func main() async throws {
        let arguments = CommandLine.arguments
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

        let campaign = try ModelWorkflowFaultCampaign(seed: 24).run(
            operationCount: 1_000
        )
        let evidence = ModelFaultVerifierEvidence(
            schemaVersion: 1,
            campaign: campaign,
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
    let downloadService: DeterministicModelDownloadReport
}

private enum Exit: Error {
    case invalidArguments
}
