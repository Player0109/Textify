import Foundation

struct BenchmarkBatchJobs: Codable {
    let schemaVersion: Int
    let items: [BenchmarkBatchItem]

    static func load(from url: URL) throws -> BenchmarkBatchJobs {
        let jobs = try JSONDecoder().decode(BenchmarkBatchJobs.self, from: Data(contentsOf: url))
        guard jobs.schemaVersion == 1 else {
            throw BenchmarkCLIError.invalidArguments(
                "Unsupported benchmark batch jobs schema: \(jobs.schemaVersion)"
            )
        }
        guard !jobs.items.isEmpty else {
            throw BenchmarkCLIError.invalidArguments("Benchmark batch jobs must not be empty")
        }

        let allowedIDCharacters = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-"
        )
        var itemIDs = Set<String>()
        for item in jobs.items {
            guard !item.id.isEmpty,
                  item.id.unicodeScalars.allSatisfy(allowedIDCharacters.contains)
            else {
                throw BenchmarkCLIError.invalidArguments(
                    "Benchmark batch item id contains unsupported characters: \(item.id)"
                )
            }
            guard itemIDs.insert(item.id).inserted else {
                throw BenchmarkCLIError.invalidArguments(
                    "Duplicate benchmark batch item id: \(item.id)"
                )
            }
            guard FileManager.default.fileExists(atPath: item.audio) else {
                throw BenchmarkCLIError.invalidAudio(
                    "Audio file does not exist for batch item \(item.id): \(item.audio)"
                )
            }
        }
        return jobs
    }
}

struct BenchmarkBatchItem: Codable {
    let id: String
    let audio: String
    let reference: String
}

struct BenchmarkBatchSessionSummary: Codable {
    let schemaVersion: Int
    let engine: BenchmarkEngine
    let model: String
    let feedMode: FeedMode
    let host: HostSnapshot
    let modelLoadCount: Int
    let modelLoadMs: Int
    let warmupCount: Int
    let warmupMs: Int
    let completedItems: Int
}

enum BatchBenchmark {
    static func run(options: BenchmarkOptions) async throws {
        guard let jobsURL = options.batchJobsURL,
              let outputDirectoryURL = options.batchOutputDirectoryURL
        else {
            throw BenchmarkCLIError.invalidArguments("Resident batch mode is missing required paths")
        }

        let jobs = try BenchmarkBatchJobs.load(from: jobsURL)
        try FileManager.default.createDirectory(
            at: outputDirectoryURL,
            withIntermediateDirectories: true
        )
        let session = try ResidentBenchmarkSessionFactory.make(options: options)
        try await session.load()

        var completedItems = 0
        do {
            for item in jobs.items {
                let audioURL = URL(fileURLWithPath: item.audio).standardizedFileURL
                let audio = try CanonicalBenchmarkAudio.load(from: audioURL)
                guard !audio.samples.isEmpty else {
                    throw BenchmarkCLIError.invalidAudio(
                        "Audio file contains no samples for batch item: \(item.id)"
                    )
                }
                let result = try await session.transcribe(
                    audio: audio,
                    reference: item.reference
                )
                try writeJSON(
                    result,
                    to: outputDirectoryURL.appendingPathComponent("\(item.id).json")
                )
                completedItems += 1
            }
        } catch {
            await session.unload()
            throw error
        }
        await session.unload()

        let summary = BenchmarkBatchSessionSummary(
            schemaVersion: 1,
            engine: session.engine,
            model: session.modelName,
            feedMode: options.feedMode,
            host: .current(),
            modelLoadCount: 1,
            modelLoadMs: session.modelLoadMs,
            warmupCount: 1,
            warmupMs: session.warmupMs,
            completedItems: completedItems
        )
        try writeJSON(
            summary,
            to: outputDirectoryURL.appendingPathComponent("batch-session.json")
        )
        print(outputDirectoryURL.path)
    }
}

private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(value).write(to: url, options: .atomic)
}
