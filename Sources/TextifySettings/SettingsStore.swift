import Foundation

public enum SettingsStorage: Equatable, Sendable {
    case memory
    case file(URL)
}

public final class SettingsStore {
    public let storage: SettingsStorage
    public private(set) var lastError: SettingsStoreError?

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
        let data: Data?
        do {
            data = try loadData()
        } catch {
            lastError = .loadingFailed
            return .defaults
        }

        guard let data else {
            lastError = nil
            return .defaults
        }

        let preferences: AppPreferences
        do {
            preferences = try decoder.decode(AppPreferences.self, from: data)
        } catch {
            lastError = .decodingFailed
            return .defaults
        }

        if requiresDockPreferenceMigration(data) {
            do {
                try saveData(encoder.encode(preferences))
            } catch {
                lastError = .savingFailed
                return preferences
            }
        }

        lastError = nil
        return preferences
    }

    public func save(_ preferences: AppPreferences) {
        let data: Data
        do {
            data = try encoder.encode(preferences)
        } catch {
            lastError = .encodingFailed
            return
        }

        do {
            try saveData(data)
            lastError = nil
        } catch {
            lastError = .savingFailed
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

    private func requiresDockPreferenceMigration(_ data: Data) -> Bool {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any]
        else {
            return false
        }

        return dictionary["keepTextifyInDock"] == nil
    }
}
