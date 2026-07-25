import Darwin
import Foundation

enum ReleaseEvidenceFilePolicy {
    static func accepts(_ url: URL, in root: URL) -> Bool {
        let standardizedRoot =
            root.resolvingSymlinksInPath().standardizedFileURL
        let standardizedURL =
            url.resolvingSymlinksInPath().standardizedFileURL
        let rootPath = standardizedRoot.path.hasSuffix("/")
            ? standardizedRoot.path
            : standardizedRoot.path + "/"
        guard standardizedURL.path.hasPrefix(rootPath) else {
            return false
        }
        var information = stat()
        guard lstat(url.path, &information) == 0 else {
            return false
        }
        return information.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG)
            && information.st_nlink == 1
    }
}
