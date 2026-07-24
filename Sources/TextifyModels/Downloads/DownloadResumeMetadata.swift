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

enum ModelDownloadStorageValidation {
    static func validatedPartialURL(
        for metadataURL: URL,
        expectedModelID: String? = nil,
        expectedFiles: [ModelFile]? = nil,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let metadata = try? JSONDecoder().decode(
            DownloadResumeMetadata.self,
            from: Data(contentsOf: metadataURL)
        ),
        expectedModelID == nil || metadata.modelID == expectedModelID,
        expectedFiles == nil || expectedFiles?.contains(where: { file in
            metadata.url == file.url
                && metadata.expectedSize == file.sizeBytes
                && metadata.sha256.lowercased() == file.sha256.lowercased()
        }) == true,
        metadata.bytesDownloaded > 0,
        metadata.bytesDownloaded < metadata.expectedSize,
        isSHA256(metadata.sha256),
        hasValidator(metadata),
        let sourceURL = URL(string: metadata.url),
        (try? ModelDownloadURLPolicy.requireApprovedModelFile(sourceURL)) != nil,
        let partialURL = partialURL(for: metadataURL),
        let values = try? partialURL.resourceValues(
            forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        ),
        values.isRegularFile == true,
        values.isSymbolicLink != true,
        Int64(values.fileSize ?? -1) == metadata.bytesDownloaded,
        fileManager.fileExists(atPath: partialURL.path)
        else {
            return nil
        }
        return partialURL
    }

    private static func partialURL(for metadataURL: URL) -> URL? {
        let suffix = ".resume.json"
        let filename = metadataURL.lastPathComponent
        guard filename.hasSuffix(suffix) else {
            return nil
        }
        return metadataURL.deletingLastPathComponent().appendingPathComponent(
            String(filename.dropLast(suffix.count)),
            isDirectory: false
        )
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.count == 64
            && value.unicodeScalars.allSatisfy {
                CharacterSet(charactersIn: "0123456789abcdef").contains($0)
            }
    }

    private static func hasValidator(
        _ metadata: DownloadResumeMetadata
    ) -> Bool {
        [metadata.eTag, metadata.lastModified]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains { !$0.isEmpty }
    }
}
