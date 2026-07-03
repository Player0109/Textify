@preconcurrency import AVFoundation
import Foundation

public struct CanonicalAudioConverter: Sendable {
    fileprivate static let canonicalSampleRate: Double = 16_000
    fileprivate static let canonicalChannelCount: AVAudioChannelCount = 1

    public init() {}

    public func makeSession() -> CanonicalAudioConversionSession {
        CanonicalAudioConversionSession()
    }

    public func convert(_ buffer: AVAudioPCMBuffer) throws -> CanonicalAudioBuffer {
        let session = makeSession()
        let converted = try session.convert(buffer)
        let drained = try session.finish()
        guard !drained.isEmpty else {
            return converted
        }

        return CanonicalAudioBuffer(
            sampleRate: converted.sampleRate,
            channelCount: converted.channelCount,
            samples: converted.samples + drained.samples
        )
    }

    fileprivate static func isCanonical(_ format: AVAudioFormat) -> Bool {
        format.commonFormat == .pcmFormatFloat32
            && Int(format.sampleRate) == Int(canonicalSampleRate)
            && format.channelCount == canonicalChannelCount
            && !format.isInterleaved
    }

    fileprivate static func makeCanonicalFormat() throws -> AVAudioFormat {
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

    fileprivate static func makeMonoBuffer(from buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
        guard buffer.format.commonFormat == .pcmFormatFloat32,
              buffer.floatChannelData != nil else {
            throw LiveAudioRecorderError.unsupportedInputFormat
        }

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

    fileprivate static func canonicalBuffer(from buffer: AVAudioPCMBuffer) throws -> CanonicalAudioBuffer {
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

public final class CanonicalAudioConversionSession: @unchecked Sendable {
    private let lock = NSLock()
    private var sourceFormatSignature: AudioFormatSignature?
    private var converter: AVAudioConverter?
    private var canonicalFormat: AVAudioFormat?
    private var totalSourceFrames = 0
    private var emittedOutputFrames = 0
    private var pendingOutputSamples: [Float] = []
    private var finished = false

    public init() {}

    public func convert(_ buffer: AVAudioPCMBuffer) throws -> CanonicalAudioBuffer {
        lock.lock()
        defer { lock.unlock() }

        guard !finished else {
            throw LiveAudioRecorderError.conversionFailed
        }

        return try convertLocked(buffer)
    }

    public func finish() throws -> CanonicalAudioBuffer {
        lock.lock()
        defer { lock.unlock() }

        guard !finished else {
            return CanonicalAudioBuffer(samples: [])
        }
        finished = true

        guard let converter, let canonicalFormat else {
            return CanonicalAudioBuffer(samples: [])
        }

        let drained = try drainLocked(converter: converter, canonicalFormat: canonicalFormat)
        pendingOutputSamples.append(contentsOf: drained.samples)
        return emitExpectedOutputLocked()
    }

    private func convertLocked(_ buffer: AVAudioPCMBuffer) throws -> CanonicalAudioBuffer {
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

        let monoBuffer = try CanonicalAudioConverter.makeMonoBuffer(from: buffer)
        let signature = AudioFormatSignature(format: monoBuffer.format)
        if let sourceFormatSignature {
            guard sourceFormatSignature == signature else {
                throw LiveAudioRecorderError.deviceChangedDuringRecording
            }
        } else {
            sourceFormatSignature = signature
        }

        guard !CanonicalAudioConverter.isCanonical(monoBuffer.format) else {
            return try CanonicalAudioConverter.canonicalBuffer(from: monoBuffer)
        }

        let canonicalFormat = try canonicalFormat ?? CanonicalAudioConverter.makeCanonicalFormat()
        self.canonicalFormat = canonicalFormat

        let converter: AVAudioConverter
        if let existingConverter = self.converter {
            converter = existingConverter
        } else {
            guard let newConverter = AVAudioConverter(from: monoBuffer.format, to: canonicalFormat) else {
                throw LiveAudioRecorderError.unsupportedInputFormat
            }
            newConverter.primeMethod = .none
            self.converter = newConverter
            converter = newConverter
        }

        let converted = try convertMonoBufferLocked(monoBuffer, converter: converter, canonicalFormat: canonicalFormat)
        totalSourceFrames += Int(monoBuffer.frameLength)
        pendingOutputSamples.append(contentsOf: converted.samples)
        return emitExpectedOutputLocked()
    }

    private func convertMonoBufferLocked(
        _ monoBuffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        canonicalFormat: AVAudioFormat
    ) throws -> CanonicalAudioBuffer {
        let inputProvider = SingleBufferInputProvider(buffer: monoBuffer)
        var convertedSamples: [Float] = []

        while true {
            let ratio = CanonicalAudioConverter.canonicalSampleRate / monoBuffer.format.sampleRate
            let outputCapacity = max(
                1,
                AVAudioFrameCount((Double(monoBuffer.frameLength) * ratio).rounded(.up)) + 512
            )
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: canonicalFormat, frameCapacity: outputCapacity) else {
                throw LiveAudioRecorderError.conversionFailed
            }

            var conversionError: NSError?
            let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
                inputProvider.provide(outStatus)
            }

            convertedSamples.append(contentsOf: try CanonicalAudioConverter.canonicalBuffer(from: outputBuffer).samples)

            switch status {
            case .haveData:
                guard outputBuffer.frameLength > 0 else {
                    return CanonicalAudioBuffer(samples: convertedSamples)
                }
            case .inputRanDry, .endOfStream:
                return CanonicalAudioBuffer(samples: convertedSamples)
            case .error:
                throw LiveAudioRecorderError.conversionFailed
            @unknown default:
                throw LiveAudioRecorderError.conversionFailed
            }
        }
    }

    private func drainLocked(
        converter: AVAudioConverter,
        canonicalFormat: AVAudioFormat
    ) throws -> CanonicalAudioBuffer {
        let inputProvider = EndOfStreamInputProvider()
        var drainedSamples: [Float] = []

        while true {
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: canonicalFormat, frameCapacity: 4_096) else {
                throw LiveAudioRecorderError.conversionFailed
            }

            var conversionError: NSError?
            let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
                inputProvider.provide(outStatus)
            }

            drainedSamples.append(contentsOf: try CanonicalAudioConverter.canonicalBuffer(from: outputBuffer).samples)

            switch status {
            case .haveData:
                guard outputBuffer.frameLength > 0 else {
                    return CanonicalAudioBuffer(samples: drainedSamples)
                }
            case .inputRanDry, .endOfStream:
                return CanonicalAudioBuffer(samples: drainedSamples)
            case .error:
                throw LiveAudioRecorderError.conversionFailed
            @unknown default:
                throw LiveAudioRecorderError.conversionFailed
            }
        }
    }

    private func emitExpectedOutputLocked() -> CanonicalAudioBuffer {
        guard let sourceFormatSignature else {
            return CanonicalAudioBuffer(samples: [])
        }

        let expectedTotalFrames = Int(
            (Double(totalSourceFrames) * CanonicalAudioConverter.canonicalSampleRate / sourceFormatSignature.sampleRate)
                .rounded()
        )
        let framesToEmit = max(0, expectedTotalFrames - emittedOutputFrames)
        let emittedCount = min(framesToEmit, pendingOutputSamples.count)
        guard emittedCount > 0 else {
            return CanonicalAudioBuffer(samples: [])
        }

        let samples = Array(pendingOutputSamples.prefix(emittedCount))
        pendingOutputSamples.removeFirst(emittedCount)
        emittedOutputFrames += emittedCount
        return CanonicalAudioBuffer(samples: samples)
    }
}

private struct AudioFormatSignature: Equatable {
    let commonFormat: AVAudioCommonFormat
    let sampleRate: Double
    let channelCount: AVAudioChannelCount
    let isInterleaved: Bool

    init(format: AVAudioFormat) {
        self.commonFormat = format.commonFormat
        self.sampleRate = format.sampleRate
        self.channelCount = format.channelCount
        self.isInterleaved = format.isInterleaved
    }
}

private final class SingleBufferInputProvider: @unchecked Sendable {
    private let lock = NSLock()
    private let buffer: AVAudioPCMBuffer
    private var didProvideInput = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func provide(_ outStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        lock.lock()
        defer { lock.unlock() }

        guard !didProvideInput else {
            outStatus.pointee = .noDataNow
            return nil
        }

        didProvideInput = true
        outStatus.pointee = .haveData
        return buffer
    }
}

private final class EndOfStreamInputProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var didEndStream = false

    func provide(_ outStatus: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        lock.lock()
        defer { lock.unlock() }

        guard !didEndStream else {
            outStatus.pointee = .noDataNow
            return nil
        }

        didEndStream = true
        outStatus.pointee = .endOfStream
        return nil
    }
}
