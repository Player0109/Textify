@preconcurrency import AVFoundation

public struct CanonicalAudioConverter: Sendable {
    private static let canonicalSampleRate: Double = 16_000
    private static let canonicalChannelCount: AVAudioChannelCount = 1

    public init() {}

    public func convert(_ buffer: AVAudioPCMBuffer) throws -> CanonicalAudioBuffer {
        guard buffer.format.commonFormat == .pcmFormatFloat32,
              buffer.floatChannelData != nil else {
            throw LiveAudioRecorderError.unsupportedInputFormat
        }

        let sourceFrameCount = Int(buffer.frameLength)
        guard sourceFrameCount > 0 else {
            return CanonicalAudioBuffer(samples: [])
        }

        let sourceRate = Int(buffer.format.sampleRate)
        guard sourceRate > 0 else {
            throw LiveAudioRecorderError.unsupportedInputFormat
        }

        let channelCount = Int(buffer.format.channelCount)
        guard channelCount > 0 else {
            throw LiveAudioRecorderError.unsupportedInputFormat
        }

        let monoBuffer = try Self.makeMonoBuffer(from: buffer)
        guard !Self.isCanonical(monoBuffer.format) else {
            return try Self.canonicalBuffer(from: monoBuffer)
        }

        let canonicalFormat = try Self.makeCanonicalFormat()
        guard let converter = AVAudioConverter(from: monoBuffer.format, to: canonicalFormat) else {
            throw LiveAudioRecorderError.unsupportedInputFormat
        }
        converter.primeMethod = .none

        let ratio = Self.canonicalSampleRate / monoBuffer.format.sampleRate
        let outputCapacity = max(1, AVAudioFrameCount((Double(monoBuffer.frameLength) * ratio).rounded(.up)) + 8)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: canonicalFormat, frameCapacity: outputCapacity) else {
            throw LiveAudioRecorderError.conversionFailed
        }

        var didProvideInput = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            guard !didProvideInput else {
                outStatus.pointee = .noDataNow
                return nil
            }

            didProvideInput = true
            outStatus.pointee = .haveData
            return monoBuffer
        }

        switch status {
        case .haveData, .inputRanDry, .endOfStream:
            return try Self.canonicalBuffer(from: outputBuffer)
        case .error:
            throw LiveAudioRecorderError.conversionFailed
        @unknown default:
            throw LiveAudioRecorderError.conversionFailed
        }
    }

    private static func isCanonical(_ format: AVAudioFormat) -> Bool {
        format.commonFormat == .pcmFormatFloat32
            && Int(format.sampleRate) == Int(canonicalSampleRate)
            && format.channelCount == canonicalChannelCount
            && !format.isInterleaved
    }

    private static func makeCanonicalFormat() throws -> AVAudioFormat {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: canonicalSampleRate,
            channels: canonicalChannelCount,
            interleaved: false
        ) else {
            throw LiveAudioRecorderError.unsupportedInputFormat
        }
        return format
    }

    private static func makeMonoBuffer(from buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard buffer.format.channelCount > 1 else {
            return buffer
        }
        guard let sourceData = buffer.floatChannelData else {
            throw LiveAudioRecorderError.unsupportedInputFormat
        }
        guard let monoFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: buffer.format.sampleRate,
            channels: canonicalChannelCount,
            interleaved: false
        ) else {
            throw LiveAudioRecorderError.unsupportedInputFormat
        }
        guard let monoBuffer = AVAudioPCMBuffer(pcmFormat: monoFormat, frameCapacity: buffer.frameLength) else {
            throw LiveAudioRecorderError.conversionFailed
        }

        monoBuffer.frameLength = buffer.frameLength
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard let monoChannelData = monoBuffer.floatChannelData else {
            throw LiveAudioRecorderError.unsupportedInputFormat
        }
        let monoData = monoChannelData[0]
        for frame in 0..<frameCount {
            var sum: Float = 0
            for channel in 0..<channelCount {
                sum += sourceData[channel][frame]
            }
            monoData[frame] = sum / Float(channelCount)
        }

        return monoBuffer
    }

    private static func canonicalBuffer(from buffer: AVAudioPCMBuffer) throws -> CanonicalAudioBuffer {
        guard let channelData = buffer.floatChannelData else {
            throw LiveAudioRecorderError.unsupportedInputFormat
        }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else {
            return CanonicalAudioBuffer(samples: [])
        }

        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        return CanonicalAudioBuffer(sampleRate: 16_000, channelCount: 1, samples: samples)
    }
}
