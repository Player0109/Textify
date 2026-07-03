public struct SpeechActivityDetector: Equatable, Sendable {
    public private(set) var speechDetected: Bool

    private var noiseFloorDBFS: Float
    private var ingestedFrameCount: Int
    private var sustainedCandidateFrameCount: Int

    private let frameDurationMilliseconds: Int
    private let startupGraceMilliseconds: Int
    private let sustainedSpeechMilliseconds: Int
    private let signalToNoiseThresholdDB: Float
    private let absoluteSpeechThresholdDBFS: Float

    public init(
        initialNoiseFloorDBFS: Float = -60.0,
        frameDurationMilliseconds: Int = 20,
        startupGraceMilliseconds: Int = 80,
        sustainedSpeechMilliseconds: Int = 120,
        signalToNoiseThresholdDB: Float = 12.0,
        absoluteSpeechThresholdDBFS: Float = -45.0
    ) {
        self.speechDetected = false
        self.noiseFloorDBFS = initialNoiseFloorDBFS
        self.ingestedFrameCount = 0
        self.sustainedCandidateFrameCount = 0
        self.frameDurationMilliseconds = frameDurationMilliseconds
        self.startupGraceMilliseconds = startupGraceMilliseconds
        self.sustainedSpeechMilliseconds = sustainedSpeechMilliseconds
        self.signalToNoiseThresholdDB = signalToNoiseThresholdDB
        self.absoluteSpeechThresholdDBFS = absoluteSpeechThresholdDBFS
    }

    public mutating func ingest(frameRMSdBFS: Float) {
        guard frameRMSdBFS.isFinite else {
            resetCandidateStreak()
            return
        }

        ingestedFrameCount += 1

        let candidateThreshold = max(
            noiseFloorDBFS + signalToNoiseThresholdDB,
            absoluteSpeechThresholdDBFS
        )
        let candidate = !isInStartupGrace && frameRMSdBFS > candidateThreshold

        if candidate {
            sustainedCandidateFrameCount += 1
        } else {
            resetCandidateStreak()
            updateNoiseFloor(with: frameRMSdBFS)
        }

        if sustainedCandidateDurationMilliseconds >= sustainedSpeechMilliseconds {
            speechDetected = true
        }
    }

    private var isInStartupGrace: Bool {
        ingestedFrameCount * frameDurationMilliseconds <= startupGraceMilliseconds
    }

    private var sustainedCandidateDurationMilliseconds: Int {
        sustainedCandidateFrameCount * frameDurationMilliseconds
    }

    private mutating func resetCandidateStreak() {
        sustainedCandidateFrameCount = 0
    }

    private mutating func updateNoiseFloor(with frameRMSdBFS: Float) {
        let quietSample = min(frameRMSdBFS, absoluteSpeechThresholdDBFS)
        noiseFloorDBFS = noiseFloorDBFS * 0.95 + quietSample * 0.05
    }
}
