public struct SpokenCommand: Equatable, Sendable {
    enum Spacing: Equatable, Sendable {
        case attachingPunctuation
        case openQuote
        case closeQuote
        case newline
        case newParagraph
        case stripSurrounding
        case spaced
        case openWrapper
        case closeWrapper
    }

    public let canonicalPhrase: String
    public let aliases: [String]
    public let output: String
    let spacing: Spacing

    var phrases: [String] {
        [canonicalPhrase] + aliases
    }

    init(canonicalPhrase: String, aliases: [String] = [], output: String, spacing: Spacing) {
        self.canonicalPhrase = canonicalPhrase
        self.aliases = aliases
        self.output = output
        self.spacing = spacing
    }

    public static let all: [SpokenCommand] = [
        SpokenCommand(canonicalPhrase: "comma", output: ",", spacing: .attachingPunctuation),
        SpokenCommand(canonicalPhrase: "period", aliases: ["full stop"], output: ".", spacing: .attachingPunctuation),
        SpokenCommand(canonicalPhrase: "exclamation mark", aliases: ["exclamation point"], output: "!", spacing: .attachingPunctuation),
        SpokenCommand(canonicalPhrase: "question mark", output: "?", spacing: .attachingPunctuation),
        SpokenCommand(canonicalPhrase: "colon", output: ":", spacing: .attachingPunctuation),
        SpokenCommand(canonicalPhrase: "semicolon", output: ";", spacing: .attachingPunctuation),
        SpokenCommand(canonicalPhrase: "open quote", output: "\"", spacing: .openQuote),
        SpokenCommand(canonicalPhrase: "close quote", output: "\"", spacing: .closeQuote),
        SpokenCommand(canonicalPhrase: "new line", output: "\n", spacing: .newline),
        SpokenCommand(canonicalPhrase: "new paragraph", output: "\n\n", spacing: .newParagraph),
        SpokenCommand(canonicalPhrase: "hyphen", output: "-", spacing: .stripSurrounding),
        SpokenCommand(canonicalPhrase: "open parenthesis", aliases: ["open paren"], output: "(", spacing: .openWrapper),
        SpokenCommand(canonicalPhrase: "close parenthesis", aliases: ["close paren"], output: ")", spacing: .closeWrapper),
        SpokenCommand(canonicalPhrase: "at sign", output: "@", spacing: .stripSurrounding),
        SpokenCommand(canonicalPhrase: "ampersand", output: "&", spacing: .spaced),
        SpokenCommand(canonicalPhrase: "forward slash", output: "/", spacing: .stripSurrounding),
        SpokenCommand(canonicalPhrase: "backslash", output: "\\", spacing: .stripSurrounding)
    ]
}
