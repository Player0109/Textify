@preconcurrency import AVFoundation
import Foundation
import TextifyWhisperShim
import XCTest

final class WhisperRuntimeTests: XCTestCase {
    func testNilNativeContextIsNotCrisperWhisper() {
        XCTAssertEqual(textify_whisper_is_crisper_model(nil), 0)
    }

    func testCrisperWhisperIntendedModeNativePathWhenLocalArtifactsAreProvided() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let modelPath = environment["TEXTIFY_CRISPERWHISPER_MODEL_PATH"],
              !modelPath.isEmpty else {
            throw XCTSkip(
                "Set TEXTIFY_CRISPERWHISPER_MODEL_PATH and TEXTIFY_CRISPERWHISPER_AUDIO_PATH " +
                "to run the local CrisperWhisper Intended-mode smoke test."
            )
        }
        guard let audioPath = environment["TEXTIFY_CRISPERWHISPER_AUDIO_PATH"],
              !audioPath.isEmpty else {
            XCTFail("TEXTIFY_CRISPERWHISPER_AUDIO_PATH must point to 16 kHz mono audio.")
            return
        }
        guard FileManager.default.fileExists(atPath: modelPath) else {
            XCTFail("The CrisperWhisper model does not exist at the configured path.")
            return
        }
        guard FileManager.default.fileExists(atPath: audioPath) else {
            XCTFail("The CrisperWhisper test audio does not exist at the configured path.")
            return
        }
        let useGPU = environment["TEXTIFY_CRISPERWHISPER_USE_GPU"] == "1"

        guard let context = textify_whisper_load(
            modelPath,
            useGPU ? 1 : 0,
            Int32(clamping: ProcessInfo.processInfo.activeProcessorCount)
        ) else {
            XCTFail("CrisperWhisper model load failed: \(Self.lastError(nil))")
            return
        }
        defer { textify_whisper_free(context) }

        XCTAssertEqual(textify_whisper_is_crisper_model(context), 1)
        XCTAssertEqual(textify_whisper_uses_gpu(context), useGPU ? 1 : 0)

        let oneSample = [Float](repeating: 0, count: 1)
        let transcribeOneSample = {
            (language: String, translate: Int32, temperature: Float, noContext: Int32, prompt: String?) in
            oneSample.withUnsafeBufferPointer { samples in
                language.withCString { languagePointer in
                    if let prompt {
                        return prompt.withCString { promptPointer in
                            textify_whisper_transcribe(
                                context,
                                samples.baseAddress,
                                Int32(samples.count),
                                languagePointer,
                                translate,
                                temperature,
                                noContext,
                                promptPointer
                            )
                        }
                    }
                    return textify_whisper_transcribe(
                        context,
                        samples.baseAddress,
                        Int32(samples.count),
                        languagePointer,
                        translate,
                        temperature,
                        noContext,
                        nil
                    )
                }
            }
        }

        let unsupportedLanguageCode = transcribeOneSample("fr", 0, 0, 1, nil)
        XCTAssertNotEqual(unsupportedLanguageCode, 0)
        XCTAssertTrue(Self.lastError(context).contains("English Intended mode only"))
        XCTAssertNotEqual(transcribeOneSample("en", 1, 0, 1, nil), 0)
        XCTAssertTrue(Self.lastError(context).contains("translation is unsupported"))
        XCTAssertNotEqual(transcribeOneSample("en", 0, 0.1, 1, nil), 0)
        XCTAssertTrue(Self.lastError(context).contains("temperature 0"))
        XCTAssertNotEqual(transcribeOneSample("en", 0, 0, 0, nil), 0)
        XCTAssertTrue(Self.lastError(context).contains("previous-context"))
        XCTAssertNotEqual(transcribeOneSample("en", 0, 0, 1, "Textify"), 0)
        XCTAssertTrue(Self.lastError(context).contains("initial prompts are unsupported"))

        let tooLong = [Float](repeating: 0, count: 30 * 16_000 + 1)
        let tooLongCode = tooLong.withUnsafeBufferPointer { samples in
            textify_whisper_transcribe(
                context,
                samples.baseAddress,
                Int32(samples.count),
                "en",
                0,
                0,
                1,
                nil
            )
        }
        XCTAssertNotEqual(tooLongCode, 0)
        XCTAssertTrue(Self.lastError(context).contains("cannot exceed 30 seconds"))

        let audio = try Self.loadPCMMono16K(from: URL(fileURLWithPath: audioPath))
        let transcriptionCode = audio.withUnsafeBufferPointer { samples in
            textify_whisper_transcribe(
                context,
                samples.baseAddress,
                Int32(samples.count),
                "en",
                0,
                0,
                1,
                nil
            )
        }
        XCTAssertEqual(transcriptionCode, 0, Self.lastError(context))

        let text = String(cString: textify_whisper_last_text(context))
        XCTAssertTrue(
            text.localizedCaseInsensitiveContains("a man said to the universe") ||
                text.localizedCaseInsensitiveContains("and so my fellow americans"),
            "Unexpected CrisperWhisper transcript: \(text)"
        )
        XCTAssertFalse(text.contains("[intended_"))
        XCTAssertFalse(text.contains("[verbatim_"))
        XCTAssertFalse(text.contains("<|"))
        XCTAssertFalse(text.contains("<vtx>"))
        XCTAssertFalse(text.contains("<ctx>"))
        XCTAssertFalse(text.contains("<htx>"))

        let noSpeechProbability = textify_whisper_last_no_speech_probability(context)
        let averageLogProbability = textify_whisper_last_average_log_probability(context)
        let compressionRatio = textify_whisper_last_compression_ratio(context)
        XCTAssertTrue(noSpeechProbability.isFinite)
        XCTAssertTrue((0 ... 1).contains(noSpeechProbability))
        XCTAssertGreaterThan(
            noSpeechProbability,
            0,
            "Expected the model-specific no-speech token probability, not a missing-token sentinel."
        )
        XCTAssertTrue(averageLogProbability.isFinite)
        XCTAssertLessThanOrEqual(averageLogProbability, 0)
        XCTAssertTrue(compressionRatio.isFinite)
        XCTAssertGreaterThanOrEqual(compressionRatio, 0)
        XCTAssertTrue(Self.lastError(context).isEmpty)
    }

    private static func lastError(_ context: OpaquePointer?) -> String {
        guard let error = textify_whisper_last_error(context) else {
            return ""
        }
        return String(cString: error)
    }

    private static func loadPCMMono16K(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        guard format.sampleRate == 16_000,
              format.channelCount == 1,
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(file.length)
              ) else {
            throw CrisperWhisperIntegrationAudioError.invalidFormat
        }
        try file.read(into: buffer)
        guard let samples = buffer.floatChannelData?.pointee else {
            throw CrisperWhisperIntegrationAudioError.invalidFormat
        }
        return Array(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength)))
    }
}

private enum CrisperWhisperIntegrationAudioError: Error {
    case invalidFormat
}
