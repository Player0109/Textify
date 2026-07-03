import Foundation

public struct RMSFrameEmitter: Sendable {
    private let frameDurationMilliseconds: Int
    private var detector: SpeechActivityDetector
    private var pendingSamples: [Float] = []
    private var hasEmitted = false

    public init(
        threshold: Float = 0.02,
        requiredSpeechFrames: Int = 5,
        frameDurationMilliseconds: Int = 20
    ) {
        self.frameDurationMilliseconds = frameDurationMilliseconds
        self.detector = SpeechActivityDetector()
    }

    public mutating func ingest(samples: [Float], sampleRate: Int) -> Bool {
        guard !samples.isEmpty, sampleRate > 0 else {
            return false
        }
        guard !hasEmitted else {
            return false
        }

        let samplesPerFrame = max(1, sampleRate * frameDurationMilliseconds / 1_000)
        pendingSamples.append(contentsOf: samples)

        while pendingSamples.count >= samplesPerFrame {
            let frame = Array(pendingSamples.prefix(samplesPerFrame))
            pendingSamples.removeFirst(samplesPerFrame)
            detector.ingest(frameRMSdBFS: Self.rmsDBFS(samples: frame))

            if detector.speechDetected {
                hasEmitted = true
                pendingSamples.removeAll(keepingCapacity: false)
                return true
            }
        }

        return false
    }

    private static func rmsDBFS(samples: [Float]) -> Float {
        let sumSquares = samples.reduce(Float(0)) { partial, sample in
            partial + sample * sample
        }
        let rms = (sumSquares / Float(samples.count)).squareRoot()
        guard rms > 0, rms.isFinite else {
            return -.infinity
        }
        return 20.0 * log10(rms)
    }
}
