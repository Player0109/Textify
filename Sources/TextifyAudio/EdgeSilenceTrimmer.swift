import Foundation

public struct EdgeSilenceTrimmer: Equatable, Sendable {
    public let silenceThresholdDBFS: Float
    public let safetyPadMilliseconds: Int

    public init(silenceThresholdDBFS: Float = -45.0, safetyPadMilliseconds: Int = 150) {
        self.silenceThresholdDBFS = silenceThresholdDBFS
        self.safetyPadMilliseconds = safetyPadMilliseconds
    }

    public func trim(_ buffer: CanonicalAudioBuffer) -> CanonicalAudioBuffer {
        guard buffer.sampleRate > 0, buffer.channelCount == 1, !buffer.samples.isEmpty else {
            return buffer
        }

        guard let firstSpeechIndex = buffer.samples.firstIndex(where: isSpeechSample),
              let lastSpeechIndex = buffer.samples.lastIndex(where: isSpeechSample) else {
            return CanonicalAudioBuffer(
                sampleRate: buffer.sampleRate,
                channelCount: buffer.channelCount,
                samples: []
            )
        }

        let safetyPadSamples = max(0, buffer.sampleRate * safetyPadMilliseconds / 1_000)
        let startIndex = max(0, firstSpeechIndex - safetyPadSamples)
        let endIndex = min(buffer.samples.count, lastSpeechIndex + 1 + safetyPadSamples)

        return CanonicalAudioBuffer(
            sampleRate: buffer.sampleRate,
            channelCount: buffer.channelCount,
            samples: Array(buffer.samples[startIndex..<endIndex])
        )
    }

    private func isSpeechSample(_ sample: Float) -> Bool {
        guard sample.isFinite else {
            return false
        }

        let magnitude = abs(sample)
        guard magnitude > 0 else {
            return false
        }

        return 20.0 * log10(magnitude) > silenceThresholdDBFS
    }
}
