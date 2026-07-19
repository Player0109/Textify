@preconcurrency import AVFoundation
import Foundation

private final class ConverterInput: @unchecked Sendable {
    private let lock = NSLock()
    private let buffer: AVAudioPCMBuffer
    private var supplied = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        lock.lock()
        defer { lock.unlock() }
        guard !supplied else {
            status.pointee = .endOfStream
            return nil
        }
        supplied = true
        status.pointee = .haveData
        return buffer
    }
}

struct CanonicalBenchmarkAudio {
    static let sampleRate = 16_000

    let samples: [Float]

    var durationMilliseconds: Int {
        Int((Double(samples.count) / Double(Self.sampleRate) * 1_000).rounded())
    }

    static func load(from url: URL) throws -> CanonicalBenchmarkAudio {
        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat
        guard let sourceBuffer = AVAudioPCMBuffer(
            pcmFormat: sourceFormat,
            frameCapacity: AVAudioFrameCount(file.length)
        ) else {
            throw BenchmarkCLIError.invalidAudio("Could not allocate a source audio buffer")
        }
        try file.read(into: sourceBuffer)

        guard let canonicalFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: sourceFormat, to: canonicalFormat)
        else {
            throw BenchmarkCLIError.invalidAudio("Could not create the 16 kHz mono converter")
        }

        let ratio = canonicalFormat.sampleRate / sourceFormat.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(sourceBuffer.frameLength) * ratio)) + 1_024
        guard let converted = AVAudioPCMBuffer(
            pcmFormat: canonicalFormat,
            frameCapacity: capacity
        ) else {
            throw BenchmarkCLIError.invalidAudio("Could not allocate the converted audio buffer")
        }

        let input = ConverterInput(buffer: sourceBuffer)
        var conversionError: NSError?
        let status = converter.convert(to: converted, error: &conversionError) { _, inputStatus in
            input.next(status: inputStatus)
        }
        if status == .error || conversionError != nil {
            throw BenchmarkCLIError.invalidAudio(
                conversionError?.localizedDescription ?? "Audio conversion failed"
            )
        }

        guard let channel = converted.floatChannelData?.pointee else {
            throw BenchmarkCLIError.invalidAudio("Converted audio has no float channel")
        }
        return CanonicalBenchmarkAudio(
            samples: Array(UnsafeBufferPointer(start: channel, count: Int(converted.frameLength)))
        )
    }

    func pcmBuffer(range: Range<Int>) throws -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(Self.sampleRate),
            channels: 1,
            interleaved: false
        ) else {
            throw BenchmarkCLIError.invalidAudio("Could not create the canonical audio format")
        }
        return try pcmBuffer(range: range, format: format)
    }

    func pcmBuffer(range: Range<Int>, format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard range.lowerBound >= 0, range.upperBound <= samples.count else {
            throw BenchmarkCLIError.invalidAudio("Audio chunk range is outside the source buffer")
        }
        guard format.sampleRate == Double(Self.sampleRate), format.channelCount == 1,
              let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(range.count)
        ) else {
            throw BenchmarkCLIError.invalidAudio("Could not allocate an audio chunk")
        }

        switch format.commonFormat {
        case .pcmFormatFloat32:
            guard let destination = buffer.floatChannelData?.pointee else {
                throw BenchmarkCLIError.invalidAudio("Float audio chunk has no channel data")
            }
            samples.withUnsafeBufferPointer { source in
                destination.update(from: source.baseAddress! + range.lowerBound, count: range.count)
            }
        case .pcmFormatInt16:
            guard let destination = buffer.int16ChannelData?.pointee else {
                throw BenchmarkCLIError.invalidAudio("Int16 audio chunk has no channel data")
            }
            for (destinationIndex, sourceIndex) in range.enumerated() {
                let scaled = (samples[sourceIndex] * Float(Int16.max)).rounded()
                destination[destinationIndex] = Int16(clamping: Int(scaled))
            }
        default:
            throw BenchmarkCLIError.invalidAudio(
                "Unsupported analyzer audio format: \(format)"
            )
        }
        buffer.frameLength = AVAudioFrameCount(range.count)
        return buffer
    }
}
