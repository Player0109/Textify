import Foundation

public struct DownloadResumeMetadata: Codable, Equatable, Sendable {
    public let modelID: String
    public let url: String
    public let expectedSize: Int64
    public let sha256: String
    public let eTag: String?
    public let lastModified: String?
    public let bytesDownloaded: Int64

    public init(
        modelID: String,
        url: String,
        expectedSize: Int64,
        sha256: String,
        eTag: String?,
        lastModified: String?,
        bytesDownloaded: Int64
    ) {
        self.modelID = modelID
        self.url = url
        self.expectedSize = expectedSize
        self.sha256 = sha256
        self.eTag = eTag
        self.lastModified = lastModified
        self.bytesDownloaded = bytesDownloaded
    }

    public func canResume(
        url: String,
        expectedSize: Int64,
        eTag: String?,
        lastModified: String?
    ) -> Bool {
        guard self.url == url,
              self.expectedSize == expectedSize,
              bytesDownloaded > 0,
              bytesDownloaded < expectedSize
        else {
            return false
        }

        var matchedValidator = false

        if let storedETag = self.eTag {
            guard storedETag == eTag else {
                return false
            }
            matchedValidator = true
        }

        if let storedLastModified = self.lastModified {
            guard storedLastModified == lastModified else {
                return false
            }
            matchedValidator = true
        }

        return matchedValidator
    }

    public func canResume(
        modelID: String,
        url: String,
        expectedSize: Int64,
        sha256: String,
        eTag: String?,
        lastModified: String?
    ) -> Bool {
        guard self.modelID == modelID,
              self.sha256.lowercased() == sha256.lowercased()
        else {
            return false
        }
        return canResume(
            url: url,
            expectedSize: expectedSize,
            eTag: eTag,
            lastModified: lastModified
        )
    }
}
