public struct DictationAudioClip: Equatable, Sendable {
    public let sampleCount: Int

    public init(sampleCount: Int = 0) {
        self.sampleCount = sampleCount
    }
}

public actor FakeDictationAudio {
    public private(set) var startedRecordingCount = 0
    public private(set) var finishedRecordingCount = 0
    public private(set) var discardedRecordingCount = 0

    private let clip: DictationAudioClip
    private let startError: DictationError?
    private let finishError: DictationError?

    public init(
        clip: DictationAudioClip = DictationAudioClip(sampleCount: 16_000),
        startError: DictationError? = nil,
        finishError: DictationError? = nil
    ) {
        self.clip = clip
        self.startError = startError
        self.finishError = finishError
    }

    public func startRecording() throws {
        if let startError {
            throw startError
        }
        startedRecordingCount += 1
    }

    public func finishRecording() throws -> DictationAudioClip {
        if let finishError {
            throw finishError
        }
        finishedRecordingCount += 1
        return clip
    }

    public func discardRecording() {
        discardedRecordingCount += 1
    }
}

public actor FakeDictationTranscriber {
    public private(set) var transcriptionCount = 0

    private var transcripts: [String]
    private let error: DictationError?

    public init(transcripts: [String] = [""], error: DictationError? = nil) {
        self.transcripts = transcripts
        self.error = error
    }

    public func transcribe(_ clip: DictationAudioClip) throws -> String {
        if let error {
            throw error
        }
        transcriptionCount += 1
        if transcripts.isEmpty {
            return ""
        }
        return transcripts.removeFirst()
    }
}

public actor FakeDictationInsertion {
    public private(set) var insertedTexts: [String] = []

    private let error: DictationError?

    public init(error: DictationError? = nil) {
        self.error = error
    }

    public func insert(_ text: String) throws {
        if let error {
            throw error
        }
        insertedTexts.append(text)
    }
}
