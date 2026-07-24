import Foundation

public enum ModelInstallError: Error, Equatable, CustomStringConvertible {
    case modelNotFound(String)
    case expectedSingleFile(count: Int)
    case invalidDownloadURL(String)
    case minimumAppVersionRequired(modelID: String, required: String, current: String)
    case storageCapacityUnavailable
    case insufficientDiskSpace(requiredBytes: Int64, availableBytes: Int64)
    case unexpectedDownloadSize(expectedBytes: Int64, actualBytes: Int64)
    case checksumMismatch(expected: String, actual: String)
    case filesystem(String)

    public var description: String {
        switch self {
        case let .modelNotFound(modelID):
            return "Model not found: \(modelID)."
        case let .expectedSingleFile(count):
            return "Expected one model file, but the manifest contains \(count)."
        case let .invalidDownloadURL(url):
            return "Invalid model download URL: \(url)."
        case let .minimumAppVersionRequired(_, required, _):
            return "This model requires Textify \(required) or newer. Update Textify and try again."
        case .storageCapacityUnavailable:
            return "Textify could not determine available model storage. Check the model volume and try again."
        case let .insufficientDiskSpace(requiredBytes, _):
            let required = ByteCountFormatter.string(fromByteCount: requiredBytes, countStyle: .file)
            return "Not enough disk space to download the model. Free at least \(required) and try again."
        case .unexpectedDownloadSize:
            return "The model download had an unexpected size. Textify deleted it; try again."
        case .checksumMismatch:
            return "The downloaded model could not be verified. Textify deleted the download; try again."
        case let .filesystem(message):
            return message
        }
    }
}
