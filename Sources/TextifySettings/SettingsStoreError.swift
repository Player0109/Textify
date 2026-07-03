public enum SettingsStoreError: Error, Equatable, Sendable {
    case loadingFailed
    case decodingFailed
    case encodingFailed
    case savingFailed
}
