import Foundation

public struct DownloadFileProgress: Codable, Equatable, Sendable {
    public let bytesDownloaded: Int64
    public let totalBytes: Int64

    public init(bytesDownloaded: Int64, totalBytes: Int64) {
        self.bytesDownloaded = max(0, bytesDownloaded)
        self.totalBytes = max(0, totalBytes)
    }
}

public enum DownloadPhase: String, CaseIterable, Codable, Equatable, Sendable {
    case checkingSpace
    case downloading
    case interrupted
    case verifying
    case installing
    case installed
    case failed
    case cancelled
}

public struct DownloadState: Codable, Equatable, Sendable {
    public let modelID: String
    public let phase: DownloadPhase
    public let bytesDownloaded: Int64
    public let totalBytes: Int64
    public let message: String?

    public init(
        modelID: String,
        phase: DownloadPhase,
        bytesDownloaded: Int64 = 0,
        totalBytes: Int64 = 0,
        message: String? = nil
    ) {
        self.modelID = modelID
        self.phase = phase
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
        self.message = message
    }

    public var progressFraction: Double {
        guard totalBytes > 0 else {
            return 0
        }

        let progress = Double(bytesDownloaded) / Double(totalBytes)
        return min(max(progress, 0), 1)
    }

    public var isActive: Bool {
        switch phase {
        case .checkingSpace, .downloading, .verifying, .installing:
            return true
        case .interrupted, .installed, .failed, .cancelled:
            return false
        }
    }
}
