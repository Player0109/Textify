import TextifyTranscription

enum RuntimeFailureCode: String, Equatable, Sendable {
    case audioTooLong = "audio_too_long"
    case automaticLanguageDetectionRequired = "automatic_language_detection_required"
    case automaticLanguageDetectionUnsupported = "automatic_language_detection_unsupported"
    case emptyAudio = "empty_audio"
    case incompatibleRuntimeConfiguration = "incompatible_runtime_configuration"
    case inferenceFailed = "inference_failed"
    case invalidAudioFormat = "invalid_audio_format"
    case missingModel = "missing_model"
    case missingRuntime = "missing_runtime"
    case modelLoadFailed = "model_load_failed"
    case modelWarmupFailed = "model_warmup_failed"
    case runtimeNotLoaded = "runtime_not_loaded"
    case runtimeUnavailable = "runtime_unavailable"
    case unsupportedLanguage = "unsupported_language"
    case unsupportedVariant = "unsupported_variant"
}

enum RuntimeFailureClassifier {
    static func code(for error: Error) -> RuntimeFailureCode {
        switch error {
        case let error as TranscribeCppRuntimeError:
            return code(for: error)
        case let error as MLXAudioRuntimeError:
            return code(for: error)
        case let error as LiteRTLMRuntimeError:
            return code(for: error)
        case let error as SherpaOnnxRuntimeError:
            return code(for: error)
        case let error as ParaformerRuntimeError:
            return code(for: error)
        case let error as ParakeetRuntimeError:
            return code(for: error)
        case let error as WhisperRuntimeError:
            return code(for: error)
        case is RuntimeTranscriptionEngineError:
            return .incompatibleRuntimeConfiguration
        default:
            return .runtimeUnavailable
        }
    }

    private static func code(for error: TranscribeCppRuntimeError) -> RuntimeFailureCode {
        switch error {
        case .missingRuntimeDirectory:
            return .missingRuntime
        case .missingModelFile:
            return .missingModel
        case .unsupportedVariant:
            return .unsupportedVariant
        case .unsupportedLanguage:
            return .unsupportedLanguage
        case .automaticLanguageDetectionUnsupported:
            return .automaticLanguageDetectionUnsupported
        case .automaticLanguageDetectionRequired:
            return .automaticLanguageDetectionRequired
        case .loadFailed:
            return .modelLoadFailed
        case .warmupFailed:
            return .modelWarmupFailed
        case .notLoaded:
            return .runtimeNotLoaded
        case .invalidAudioFormat:
            return .invalidAudioFormat
        case .emptyAudio:
            return .emptyAudio
        case .audioTooLong:
            return .audioTooLong
        case .transcriptionFailed:
            return .inferenceFailed
        }
    }

    private static func code(for error: MLXAudioRuntimeError) -> RuntimeFailureCode {
        switch error {
        case .missingModelDirectory, .missingModelFile:
            return .missingModel
        case .unsupportedVariant:
            return .unsupportedVariant
        case .unsupportedLanguage:
            return .unsupportedLanguage
        case .automaticLanguageDetectionUnsupported:
            return .automaticLanguageDetectionUnsupported
        case .automaticLanguageDetectionRequired:
            return .automaticLanguageDetectionRequired
        case .loadFailed:
            return .modelLoadFailed
        case .warmupFailed:
            return .modelWarmupFailed
        case .notLoaded:
            return .runtimeNotLoaded
        case .invalidAudioFormat:
            return .invalidAudioFormat
        case .emptyAudio:
            return .emptyAudio
        case .audioTooLong:
            return .audioTooLong
        case .transcriptionFailed:
            return .inferenceFailed
        }
    }

    private static func code(for error: LiteRTLMRuntimeError) -> RuntimeFailureCode {
        switch error {
        case .missingModelFile:
            return .missingModel
        case .unsupportedVariant:
            return .unsupportedVariant
        case .unsupportedLanguage:
            return .unsupportedLanguage
        case .automaticLanguageDetectionUnsupported:
            return .automaticLanguageDetectionUnsupported
        case .loadFailed:
            return .modelLoadFailed
        case .warmupFailed:
            return .modelWarmupFailed
        case .notLoaded:
            return .runtimeNotLoaded
        case .invalidAudioFormat:
            return .invalidAudioFormat
        case .emptyAudio:
            return .emptyAudio
        case .audioTooLong:
            return .audioTooLong
        case .temporaryAudioFailed, .transcriptionFailed:
            return .inferenceFailed
        }
    }

    private static func code(for error: SherpaOnnxRuntimeError) -> RuntimeFailureCode {
        switch error {
        case .missingRuntimeDirectory:
            return .missingRuntime
        case .missingModelDirectory, .missingModelFile:
            return .missingModel
        case .unsupportedVariant:
            return .unsupportedVariant
        case .loadFailed:
            return .modelLoadFailed
        case .warmupFailed:
            return .modelWarmupFailed
        case .notLoaded:
            return .runtimeNotLoaded
        case .invalidAudioFormat:
            return .invalidAudioFormat
        case .emptyAudio:
            return .emptyAudio
        case .audioTooLong:
            return .audioTooLong
        case .transcriptionFailed:
            return .inferenceFailed
        }
    }

    private static func code(for error: ParaformerRuntimeError) -> RuntimeFailureCode {
        switch error {
        case .missingModelDirectory:
            return .missingModel
        case .unsupportedVariant:
            return .unsupportedVariant
        case .unsupportedLanguage:
            return .unsupportedLanguage
        case .loadFailed:
            return .modelLoadFailed
        case .warmupFailed:
            return .modelWarmupFailed
        case .notLoaded:
            return .runtimeNotLoaded
        case .invalidAudioFormat:
            return .invalidAudioFormat
        case .audioTooLong:
            return .audioTooLong
        case .transcriptionFailed:
            return .inferenceFailed
        }
    }

    private static func code(for error: ParakeetRuntimeError) -> RuntimeFailureCode {
        switch error {
        case .missingModelDirectory:
            return .missingModel
        case .unsupportedVariant:
            return .unsupportedVariant
        case .loadFailed:
            return .modelLoadFailed
        case .warmupFailed:
            return .modelWarmupFailed
        case .notLoaded:
            return .runtimeNotLoaded
        case .invalidAudioFormat:
            return .invalidAudioFormat
        case .transcriptionFailed:
            return .inferenceFailed
        }
    }

    private static func code(for error: WhisperRuntimeError) -> RuntimeFailureCode {
        switch error {
        case .missingModelFile:
            return .missingModel
        case .loadFailed:
            return .modelLoadFailed
        case .warmupFailed:
            return .modelWarmupFailed
        case .notLoaded:
            return .runtimeNotLoaded
        case .invalidAudioFormat:
            return .invalidAudioFormat
        case .unsupportedTemperatureFallback:
            return .incompatibleRuntimeConfiguration
        case .transcriptionFailed:
            return .inferenceFailed
        }
    }
}
