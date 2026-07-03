public struct WhisperTranscriptionOptions: Equatable, Sendable {
    public let language: String
    public let translate: Bool
    public let temperature: Float
    public let temperatureFallback: [Float]
    public let usePreviousContext: Bool
    public let initialPrompt: String?

    public init(
        language: String,
        translate: Bool,
        temperature: Float,
        temperatureFallback: [Float],
        usePreviousContext: Bool,
        initialPrompt: String?
    ) {
        self.language = language
        self.translate = translate
        self.temperature = temperature
        self.temperatureFallback = temperatureFallback
        self.usePreviousContext = usePreviousContext
        self.initialPrompt = initialPrompt
    }

    public static let v1_1English = WhisperTranscriptionOptions(
        language: "en",
        translate: false,
        temperature: 0,
        temperatureFallback: [],
        usePreviousContext: false,
        initialPrompt: nil
    )
}
