import TextifyCore
import TextifySettings

public struct RuntimePostProcessingAdapter: RuntimePostProcessing {
    public init() {}

    public func process(rawText: String, preferences: AppPreferences) async -> String {
        PostProcessingPipeline().process(rawText: rawText, replacements: [])
    }
}
