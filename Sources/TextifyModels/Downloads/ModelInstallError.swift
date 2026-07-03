public enum ModelInstallError: Error, Equatable {
    case modelNotFound(String)
    case expectedSingleFile(count: Int)
    case invalidDownloadURL(String)
    case checksumMismatch(expected: String, actual: String)
    case filesystem(String)
}
