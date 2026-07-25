import Foundation
import TextifyReleaseVerification

@main
enum TextifyReleaseEvidenceVerifier {
    static func main() {
        do {
            try run()
        } catch {
            FileHandle.standardError.write(
                Data("release evidence rejected: \(error)\n".utf8)
            )
            exit(1)
        }
    }

    private static func run() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 6 else {
            FileHandle.standardError.write(
                Data(
                    """
                    usage: TextifyReleaseEvidenceVerifier \
                    <declaration.json> <evidence-root> <SPEC.md> \
                    <expected-release-commit> <bundle-output.json>

                    """.utf8
                )
            )
            throw Exit.invalidArguments
        }
        let declarationURL = URL(fileURLWithPath: arguments[1])
        let evidenceRoot = URL(fileURLWithPath: arguments[2], isDirectory: true)
        let specificationURL = URL(fileURLWithPath: arguments[3])
        let expectedCommit = arguments[4]
        let outputURL = URL(fileURLWithPath: arguments[5])

        let declaration = try JSONDecoder().decode(
            ReleaseCandidateEvidenceDeclaration.self,
            from: Data(contentsOf: declarationURL)
        )
        let bundle = try ReleaseCandidateEvidenceValidator().validate(
            declaration,
            evidenceRoot: evidenceRoot,
            specificationURL: specificationURL,
            expectedReleaseCommitSHA: expectedCommit
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [
            .prettyPrinted,
            .sortedKeys,
            .withoutEscapingSlashes
        ]
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(bundle).write(to: outputURL, options: .atomic)
    }
}

private enum Exit: Error {
    case invalidArguments
}
