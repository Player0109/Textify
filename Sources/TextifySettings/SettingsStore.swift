import Foundation

public enum SettingsStorage: Equatable, Sendable {
    case memory
    case file(URL)
}

public final class SettingsStore {
    public let storage: SettingsStorage
    public private(set) var lastError: Error?

    private var memoryData: Data?
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder
    private let fileManager: FileManager

    public init(storage: SettingsStorage, fileManager: FileManager = .default) {
        self.storage = storage
        self.fileManager = fileManager

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
    }

    public func load() -> AppPreferences {
        do {
            guard let data = try loadData() else {
                lastError = nil
                return .defaults
            }

            lastError = nil
            return try decoder.decode(AppPreferences.self, from: data)
        } catch {
            lastError = error
            return .defaults
        }
    }

    public func save(_ preferences: AppPreferences) {
        do {
            let data = try encoder.encode(preferences)
            try saveData(data)
            lastError = nil
        } catch {
            lastError = error
        }
    }

    public func resetOnboarding() {
        var preferences = load()
        preferences.resetOnboardingState()
        save(preferences)
    }

    public func resetAllSettings() {
        save(.defaults)
    }

    private func loadData() throws -> Data? {
        switch storage {
        case .memory:
            return memoryData
        case let .file(url):
            guard fileManager.fileExists(atPath: url.path) else {
                return nil
            }

            return try Data(contentsOf: url)
        }
    }

    private func saveData(_ data: Data) throws {
        switch storage {
        case .memory:
            memoryData = data
        case let .file(url):
            let directory = url.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
        }
    }
}
