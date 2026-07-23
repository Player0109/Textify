import Foundation

public struct EvaluationSuiteManifest: Codable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public let name: String
    public let language: String
    public let dataset: EvaluationDatasetSource
    public let durationLanes: [EvaluationDurationLane]
    public let requiredDurationBuckets: [EvaluationDurationBucket]
    public let subsets: [EvaluationSubset]
    public let items: [EvaluationCorpusItem]

    public static func decode(_ data: Data) throws -> EvaluationSuiteManifest {
        let manifest = try JSONDecoder().decode(EvaluationSuiteManifest.self, from: data)
        try manifest.validate()
        return manifest
    }

    public func compatibleItems(maxAudioSeconds: Int) -> [EvaluationCorpusItem] {
        guard (1 ... 60).contains(maxAudioSeconds) else { return [] }
        return items.filter { $0.durationMs <= maxAudioSeconds * 1_000 }
    }

    private func validate() throws {
        guard (1 ... 2).contains(schemaVersion) else {
            throw EvaluationSuiteValidationError.unsupportedSchemaVersion(schemaVersion)
        }
        guard language == "en" else {
            throw EvaluationSuiteValidationError.unsupportedLanguage(language)
        }
        guard isLowercaseHex(dataset.revision, length: 40) else {
            throw EvaluationSuiteValidationError.invalidDatasetRevision(dataset.revision)
        }

        var previousLaneMaximum = 0
        var laneIDs = Set<String>()
        for lane in durationLanes {
            guard laneIDs.insert(lane.id).inserted else {
                throw EvaluationSuiteValidationError.duplicateDurationLaneID(lane.id)
            }
            guard lane.maxAudioSeconds > previousLaneMaximum, lane.maxAudioSeconds <= 60 else {
                throw EvaluationSuiteValidationError.invalidDurationLane(lane.id)
            }
            previousLaneMaximum = lane.maxAudioSeconds
        }

        var subsetsByID: [String: EvaluationSubset] = [:]
        for subset in subsets {
            guard subsetsByID[subset.id] == nil else {
                throw EvaluationSuiteValidationError.duplicateSubsetID(subset.id)
            }
            guard !subset.config.isEmpty, !subset.split.isEmpty,
                  !subset.license.isEmpty, URL(string: subset.sourceURL)?.scheme == "https"
            else {
                throw EvaluationSuiteValidationError.invalidSubsetMetadata(subset.id)
            }
            guard subset.speechOrigin != .noSpeech || subset.role == .negativeControl else {
                throw EvaluationSuiteValidationError.invalidNoSpeechRole(subset.id)
            }
            subsetsByID[subset.id] = subset
        }

        var itemIDs = Set<String>()
        var observedBuckets: [String: Set<EvaluationDurationBucket>] = [:]
        for item in items {
            guard itemIDs.insert(item.id).inserted else {
                throw EvaluationSuiteValidationError.duplicateItemID(item.id)
            }
            guard let subset = subsetsByID[item.subsetID] else {
                throw EvaluationSuiteValidationError.unknownSubsetID(item.subsetID)
            }
            guard item.row >= 0 else {
                throw EvaluationSuiteValidationError.invalidRow(item.row)
            }
            guard isSafeRelativePath(item.audio) else {
                throw EvaluationSuiteValidationError.unsafeAudioPath(item.audio)
            }
            let referenceIsEmpty = item.reference
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
            if subset.speechOrigin == .noSpeech {
                guard referenceIsEmpty else {
                    throw EvaluationSuiteValidationError.unexpectedNoSpeechReference(item.id)
                }
            } else {
                guard !referenceIsEmpty else {
                    throw EvaluationSuiteValidationError.emptyReference(item.id)
                }
            }
            guard item.durationMs >= 1_000, item.durationMs <= 60_000,
                  item.durationBucket.contains(durationMs: item.durationMs)
            else {
                throw EvaluationSuiteValidationError.invalidDuration(item.id)
            }
            guard item.sizeBytes > 0 else {
                throw EvaluationSuiteValidationError.invalidFileSize(item.id)
            }
            guard isLowercaseHex(item.sha256, length: 64) else {
                throw EvaluationSuiteValidationError.invalidSHA256(item.id)
            }

            var buckets = observedBuckets[item.subsetID, default: []]
            if schemaVersion == 1, buckets.contains(item.durationBucket) {
                throw EvaluationSuiteValidationError.duplicateDurationBucket(
                    subsetID: item.subsetID,
                    bucket: item.durationBucket
                )
            }
            buckets.insert(item.durationBucket)
            observedBuckets[item.subsetID] = buckets

            if let speakerID = item.speakerID,
               speakerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                throw EvaluationSuiteValidationError.invalidItemMetadata(item.id)
            }
            if let slices = item.slices,
               slices.contains(where: {
                   $0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                       || $0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
               })
            {
                throw EvaluationSuiteValidationError.invalidItemMetadata(item.id)
            }
        }

        for subset in subsets {
            let buckets = observedBuckets[subset.id, default: []]
            for requiredBucket in requiredDurationBuckets where !buckets.contains(requiredBucket) {
                throw EvaluationSuiteValidationError.missingDurationBucket(
                    subsetID: subset.id,
                    bucket: requiredBucket
                )
            }
        }
    }
}

public struct EvaluationDatasetSource: Codable, Sendable {
    public let id: String
    public let revision: String
    public let viewerBaseURL: String
}

public struct EvaluationDurationLane: Codable, Sendable {
    public let id: String
    public let maxAudioSeconds: Int
}

public struct EvaluationSubset: Codable, Sendable {
    public let id: String
    public let config: String
    public let split: String
    public let role: EvaluationBenchmarkRole
    public let speechOrigin: EvaluationSpeechOrigin
    public let license: String
    public let sourceURL: String
}

public struct EvaluationCorpusItem: Codable, Sendable {
    public let id: String
    public let subsetID: String
    public let row: Int
    public let audio: String
    public let reference: String
    public let durationMs: Int
    public let durationBucket: EvaluationDurationBucket
    public let sizeBytes: Int64
    public let sha256: String
    public let speakerID: String?
    public let slices: [String: String]?

    public init(
        id: String,
        subsetID: String,
        row: Int,
        audio: String,
        reference: String,
        durationMs: Int,
        durationBucket: EvaluationDurationBucket,
        sizeBytes: Int64,
        sha256: String,
        speakerID: String? = nil,
        slices: [String: String]? = nil
    ) {
        self.id = id
        self.subsetID = subsetID
        self.row = row
        self.audio = audio
        self.reference = reference
        self.durationMs = durationMs
        self.durationBucket = durationBucket
        self.sizeBytes = sizeBytes
        self.sha256 = sha256
        self.speakerID = speakerID
        self.slices = slices
    }
}

public enum EvaluationBenchmarkRole: String, Codable, Sendable {
    case publicQuality = "public-quality"
    case productDiagnostic = "product-diagnostic"
    case stress
    case enhancement
    case negativeControl = "negative-control"
}

public enum EvaluationSpeechOrigin: String, Codable, Sendable {
    case humanRead = "human-read"
    case humanNatural = "human-natural"
    case humanMixed = "human-mixed"
    case simulatedCorruption = "simulated-corruption"
    case noSpeech = "no-speech"
}

public enum EvaluationDurationBucket: String, Codable, CaseIterable, Sendable {
    case seconds1To3 = "1-3"
    case seconds3To10 = "3-10"
    case seconds10To20 = "10-20"
    case seconds20To29 = "20-29"
    case seconds29To45 = "29-45"
    case seconds45To60 = "45-60"

    fileprivate func contains(durationMs: Int) -> Bool {
        switch self {
        case .seconds1To3:
            return (1_000 ..< 3_000).contains(durationMs)
        case .seconds3To10:
            return (3_000 ..< 10_000).contains(durationMs)
        case .seconds10To20:
            return (10_000 ..< 20_000).contains(durationMs)
        case .seconds20To29:
            return (20_000 ... 29_000).contains(durationMs)
        case .seconds29To45:
            return (29_001 ..< 45_000).contains(durationMs)
        case .seconds45To60:
            return (45_000 ... 60_000).contains(durationMs)
        }
    }
}

public enum EvaluationSuiteValidationError: Error, Equatable, CustomStringConvertible {
    case unsupportedSchemaVersion(Int)
    case unsupportedLanguage(String)
    case invalidDatasetRevision(String)
    case duplicateDurationLaneID(String)
    case invalidDurationLane(String)
    case duplicateSubsetID(String)
    case invalidSubsetMetadata(String)
    case invalidNoSpeechRole(String)
    case duplicateItemID(String)
    case unknownSubsetID(String)
    case invalidRow(Int)
    case unsafeAudioPath(String)
    case emptyReference(String)
    case unexpectedNoSpeechReference(String)
    case invalidDuration(String)
    case invalidFileSize(String)
    case invalidSHA256(String)
    case invalidItemMetadata(String)
    case duplicateDurationBucket(subsetID: String, bucket: EvaluationDurationBucket)
    case missingDurationBucket(subsetID: String, bucket: EvaluationDurationBucket)

    public var description: String {
        switch self {
        case let .unsupportedSchemaVersion(version):
            return "Unsupported evaluation suite schema version: \(version)"
        case let .unsupportedLanguage(language):
            return "Evaluation suite language must be English, received: \(language)"
        case let .invalidDatasetRevision(revision):
            return "Dataset revision must be a full lowercase commit SHA: \(revision)"
        case let .duplicateDurationLaneID(id):
            return "Duplicate duration lane id: \(id)"
        case let .invalidDurationLane(id):
            return "Duration lanes must have ascending maxima no greater than 60 seconds: \(id)"
        case let .duplicateSubsetID(id):
            return "Duplicate subset id: \(id)"
        case let .invalidSubsetMetadata(id):
            return "Subset metadata is incomplete or does not use an HTTPS source: \(id)"
        case let .invalidNoSpeechRole(id):
            return "No-speech subset must use the negative-control role: \(id)"
        case let .duplicateItemID(id):
            return "Duplicate corpus item id: \(id)"
        case let .unknownSubsetID(id):
            return "Corpus item references unknown subset: \(id)"
        case let .invalidRow(row):
            return "Dataset Viewer row must be non-negative: \(row)"
        case let .unsafeAudioPath(path):
            return "Audio path must be a safe relative path: \(path)"
        case let .emptyReference(id):
            return "Speech corpus item has an empty reference: \(id)"
        case let .unexpectedNoSpeechReference(id):
            return "No-speech corpus item must have an empty reference: \(id)"
        case let .invalidDuration(id):
            return "Corpus item duration does not match its declared bucket: \(id)"
        case let .invalidFileSize(id):
            return "Corpus item has an invalid file size: \(id)"
        case let .invalidSHA256(id):
            return "Corpus item has an invalid SHA-256: \(id)"
        case let .invalidItemMetadata(id):
            return "Corpus item has empty speaker or slice metadata: \(id)"
        case let .duplicateDurationBucket(subsetID, bucket):
            return "Subset \(subsetID) contains duplicate duration bucket \(bucket.rawValue)"
        case let .missingDurationBucket(subsetID, bucket):
            return "Subset \(subsetID) is missing duration bucket \(bucket.rawValue)"
        }
    }
}

private func isLowercaseHex(_ value: String, length: Int) -> Bool {
    let allowed = Set("0123456789abcdef")
    return value.count == length && value.allSatisfy(allowed.contains)
}

private func isSafeRelativePath(_ path: String) -> Bool {
    guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\") else {
        return false
    }
    return !path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
}
