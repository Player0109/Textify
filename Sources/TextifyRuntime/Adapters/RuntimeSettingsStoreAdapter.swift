import TextifySettings

public actor RuntimeSettingsStoreAdapter: RuntimeSettingsProviding {
    private let store: SettingsStore

    public init(store: SettingsStore) {
        self.store = store
    }

    public init(storage: SettingsStorage) {
        self.store = SettingsStore(storage: storage)
    }

    public func loadPreferences() async -> AppPreferences {
        store.load()
    }

    public func savePreferences(_ preferences: AppPreferences) async {
        store.save(preferences)
    }
}
