import AVFoundation
import Foundation
import TextifyAudio
import XCTest

final class CanonicalAudioConverterTests: XCTestCase {
    func testDownmixesStereoFloatBufferToCanonicalMono() throws {
        let buffer = try makeFloatBuffer(
            sampleRate: 16_000,
            channels: 2,
            samples: [
                [0.2, 0.4, -0.2, -0.4],
                [0.4, 0.2, -0.4, -0.2]
            ]
        )

        let converted = try CanonicalAudioConverter().convert(buffer)

        XCTAssertEqual(converted.sampleRate, 16_000)
        XCTAssertEqual(converted.channelCount, 1)
        XCTAssertEqualSamples(converted.samples, [0.3, 0.3, -0.3, -0.3])
    }

    func testResamplesToSixteenKilohertz() throws {
        let sourceSamples = (0..<480).map { Float($0) / 480.0 }
        let buffer = try makeFloatBuffer(
            sampleRate: 48_000,
            channels: 1,
            samples: [
                sourceSamples
            ]
        )

        let converted = try CanonicalAudioConverter().convert(buffer)

        XCTAssertEqual(converted.sampleRate, 16_000)
        XCTAssertEqual(converted.channelCount, 1)
        XCTAssertEqual(converted.samples.count, 160)
        XCTAssertFalse(converted.samples.allSatisfy { $0 == 0 })
    }

    func testSessionResamplesMultipleBuffersWithoutDurationDriftOrDiscontinuity() throws {
        let sourceRate = 44_100.0
        let framesPerBuffer = 1_000
        let bufferCount = 40
        let session = CanonicalAudioConverter().makeSession()
        var convertedSamples: [Float] = []

        for bufferIndex in 0..<bufferCount {
            let firstFrame = bufferIndex * framesPerBuffer
            let sourceSamples = sineSamples(
                firstFrame: firstFrame,
                count: framesPerBuffer,
                sampleRate: sourceRate
            )
            let buffer = try makeFloatBuffer(
                sampleRate: sourceRate,
                channels: 1,
                samples: [sourceSamples]
            )

            convertedSamples.append(contentsOf: try session.convert(buffer).samples)
        }

        convertedSamples.append(contentsOf: try session.finish().samples)

        let expectedFrameCount = Int((Double(framesPerBuffer * bufferCount) * 16_000.0 / sourceRate).rounded())
        XCTAssertLessThanOrEqual(abs(convertedSamples.count - expectedFrameCount), 1)
        XCTAssertFalse(convertedSamples.allSatisfy { abs($0) < 0.0001 })

        let largestAdjacentDelta = zip(convertedSamples, convertedSamples.dropFirst())
            .map { abs($1 - $0) }
            .max() ?? 0
        XCTAssertLessThan(largestAdjacentDelta, 0.25)
    }

    func testRejectsNonFloatPCMInput() throws {
        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            )
        )
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4))
        buffer.frameLength = 4

        XCTAssertThrowsError(try CanonicalAudioConverter().convert(buffer)) { error in
            XCTAssertEqual(error as? LiveAudioRecorderError, .unsupportedInputFormat)
        }
    }

    private func makeFloatBuffer(
        sampleRate: Double,
        channels: AVAudioChannelCount,
        samples: [[Float]]
    ) throws -> AVAudioPCMBuffer {
        let frameCount = try XCTUnwrap(samples.first?.count)
        let format = try XCTUnwrap(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: channels,
                interleaved: false
            )
        )
        let buffer = try XCTUnwrap(
            AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frameCount)
            )
        )
        buffer.frameLength = AVAudioFrameCount(frameCount)

        let channelData = try XCTUnwrap(buffer.floatChannelData)
        for channel in 0..<Int(channels) {
            for frame in 0..<frameCount {
                channelData[channel][frame] = samples[channel][frame]
            }
        }

        return buffer
    }

    private func sineSamples(firstFrame: Int, count: Int, sampleRate: Double) -> [Float] {
        (0..<count).map { frameOffset in
            let frame = Double(firstFrame + frameOffset)
            return Float(sin(2.0 * Double.pi * 440.0 * frame / sampleRate) * 0.4)
        }
    }

    private func XCTAssertEqualSamples(
        _ actual: [Float],
        _ expected: [Float],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        for (actualSample, expectedSample) in zip(actual, expected) {
            XCTAssertEqual(actualSample, expectedSample, accuracy: 0.0001, file: file, line: line)
        }
    }
}
