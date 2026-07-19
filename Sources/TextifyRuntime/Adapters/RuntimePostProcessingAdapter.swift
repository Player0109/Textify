import Foundation
import TextifyCore
import TextifySettings

public struct RuntimePostProcessingAdapter: RuntimePostProcessing {
    public init() {}

    public func process(rawText: String, preferences: AppPreferences) async -> String {
        guard preferences.transcriptionLanguage == .english else {
            return rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return PostProcessingPipeline().process(rawText: rawText, replacements: [])
    }
}
