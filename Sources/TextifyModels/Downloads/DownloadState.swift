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
    case queued
    case paused
    case waitingForNetwork
    case waitingForCatalogCheck
    case checkingSpace
    case downloading
    case interrupted
    case verifying
    case installing
    case installed
    case failed
    case cancelled
    case revoked

    public var isTerminal: Bool {
        switch self {
        case .interrupted, .installed, .failed, .cancelled, .revoked:
            return true
        case .queued, .paused, .waitingForNetwork, .waitingForCatalogCheck,
             .checkingSpace, .downloading, .verifying, .installing:
            return false
        }
    }

    public var isPipelineActive: Bool {
        switch self {
        case .checkingSpace, .downloading, .verifying, .installing:
            return true
        case .queued, .paused, .waitingForNetwork, .waitingForCatalogCheck,
             .interrupted, .installed, .failed, .cancelled, .revoked:
            return false
        }
    }
}

public struct DownloadState: Codable, Equatable, Sendable {
    public let modelID: String
    public let phase: DownloadPhase
    public let bytesDownloaded: Int64
    public let totalBytes: Int64
    public let message: String?
    public let attemptID: String?

    public init(
        modelID: String,
        phase: DownloadPhase,
        bytesDownloaded: Int64 = 0,
        totalBytes: Int64 = 0,
        message: String? = nil,
        attemptID: String? = nil
    ) {
        self.modelID = modelID
        self.phase = phase
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
        self.message = message
        self.attemptID = attemptID
    }

    public var progressFraction: Double {
        guard totalBytes > 0 else {
            return 0
        }

        let progress = Double(bytesDownloaded) / Double(totalBytes)
        return min(max(progress, 0), 1)
    }

    public var isActive: Bool {
        phase.isPipelineActive
    }
}
