import Foundation

public struct PostProcessingPipeline {
    private enum PipelineToken {
        case text(String)
        case command(SpokenCommand)
    }

    private struct CommandPhrase {
        let words: [String]
        let command: SpokenCommand
    }

    private let commandPhrases: [CommandPhrase]

    public init(commands: [SpokenCommand] = SpokenCommand.all) {
        commandPhrases = commands
            .flatMap { command in
                command.phrases.map { phrase in
                    CommandPhrase(words: phrase.lowercased().split(separator: " ").map(String.init), command: command)
                }
            }
            .sorted { lhs, rhs in
                if lhs.words.count == rhs.words.count {
                    return lhs.words.joined(separator: " ").count > rhs.words.joined(separator: " ").count
                }
                return lhs.words.count > rhs.words.count
            }
    }

    public func process(rawText: String, replacements: [VocabularyReplacement]) -> String {
        let commandNormalized = normalizeCommands(in: rawText)
        let deduped = deduplicateAdjacentPunctuation(in: commandNormalized)
        let cleaned = removeLightFillers(from: deduped)
        let replaced = applyVocabularyReplacements(to: cleaned, replacements: replacements)
        return formatFinalOutput(from: replaced)
    }

    private func normalizeCommands(in rawText: String) -> String {
        let words = rawText.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var tokens: [PipelineToken] = []
        var index = 0

        while index < words.count {
            if let match = commandMatch(in: words, at: index) {
                tokens.append(.command(match.command))
                index += match.words.count
            } else {
                tokens.append(.text(words[index]))
                index += 1
            }
        }

        return normalizeSpacing(render(tokens))
    }

    private func commandMatch(in words: [String], at index: Int) -> CommandPhrase? {
        for phrase in commandPhrases {
            guard index + phrase.words.count <= words.count else {
                continue
            }

            let candidate = words[index..<(index + phrase.words.count)]
                .map { normalizedCommandWord($0) }

            if candidate == phrase.words {
                return phrase
            }
        }
        return nil
    }

    private func normalizedCommandWord(_ word: String) -> String {
        word.trimmingCharacters(in: .punctuationCharacters).lowercased()
    }

    private func render(_ tokens: [PipelineToken]) -> String {
        var output = ""
        var suppressSpaceBeforeNextWord = false

        for token in tokens {
            switch token {
            case let .text(word):
                appendWord(word, to: &output, suppressSpaceBeforeNextWord: &suppressSpaceBeforeNextWord)

            case let .command(command):
                append(command, to: &output, suppressSpaceBeforeNextWord: &suppressSpaceBeforeNextWord)
            }
        }

        return output
    }

    private func appendWord(
        _ word: String,
        to output: inout String,
        suppressSpaceBeforeNextWord: inout Bool
    ) {
        if output.isEmpty || output.last?.isWhitespace == true {
            output += word
        } else if suppressSpaceBeforeNextWord {
            output += word
        } else {
            output += " " + word
        }
        suppressSpaceBeforeNextWord = false
    }

    private func append(
        _ command: SpokenCommand,
        to output: inout String,
        suppressSpaceBeforeNextWord: inout Bool
    ) {
        switch command.spacing {
        case .attachingPunctuation:
            trimTrailingHorizontalWhitespace(&output)
            output += command.output
            suppressSpaceBeforeNextWord = false

        case .openQuote:
            appendLeadingSpaceIfNeeded(to: &output)
            output += command.output
            suppressSpaceBeforeNextWord = true

        case .closeQuote:
            trimTrailingHorizontalWhitespace(&output)
            output += command.output
            suppressSpaceBeforeNextWord = false

        case .newline:
            trimTrailingHorizontalWhitespace(&output)
            output += "\n"
            suppressSpaceBeforeNextWord = false

        case .newParagraph:
            trimTrailingHorizontalWhitespace(&output)
            output += "\n\n"
            suppressSpaceBeforeNextWord = false

        case .stripSurrounding:
            trimTrailingHorizontalWhitespace(&output)
            output += command.output
            suppressSpaceBeforeNextWord = true

        case .spaced:
            trimTrailingHorizontalWhitespace(&output)
            appendLeadingSpaceIfNeeded(to: &output)
            output += command.output
            output += " "
            suppressSpaceBeforeNextWord = false

        case .openWrapper:
            appendLeadingSpaceIfNeeded(to: &output)
            output += command.output
            suppressSpaceBeforeNextWord = true

        case .closeWrapper:
            trimTrailingHorizontalWhitespace(&output)
            output += command.output
            suppressSpaceBeforeNextWord = false
        }
    }

    private func appendLeadingSpaceIfNeeded(to output: inout String) {
        if !output.isEmpty, output.last?.isWhitespace == false {
            output += " "
        }
    }

    private func trimTrailingHorizontalWhitespace(_ output: inout String) {
        while let last = output.last, last == " " || last == "\t" {
            output.removeLast()
        }
    }

    private func deduplicateAdjacentPunctuation(in text: String) -> String {
        let punctuation = Set(",.;:!?")
        var output = ""
        var lastPunctuation: Character?

        for character in text {
            if punctuation.contains(character) {
                if lastPunctuation == character {
                    continue
                }
                output.append(character)
                lastPunctuation = character
            } else if character.isWhitespace {
                output.append(character)
            } else {
                output.append(character)
                lastPunctuation = nil
            }
        }

        return normalizeSpacing(output)
    }

    private func removeLightFillers(from text: String) -> String {
        var output = text
        output = output.replacingOccurrences(
            of: #"(?i)(?<![A-Za-z0-9])(um|uh)(?![A-Za-z0-9])[, ]*"#,
            with: "",
            options: .regularExpression
        )
        output = output.replacingOccurrences(
            of: #"(?i)(?<![A-Za-z0-9])you\s+know(?![A-Za-z0-9])[, ]*"#,
            with: "",
            options: .regularExpression
        )
        output = output.replacingOccurrences(
            of: #"(?i)(^|[.!?,;:]\s+)like,?\s+"#,
            with: "$1",
            options: .regularExpression
        )
        return normalizeSpacing(output)
    }

    private func applyVocabularyReplacements(
        to text: String,
        replacements: [VocabularyReplacement]
    ) -> [TextSegment] {
        let orderedReplacements = replacements
            .filter { !$0.trigger.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { lhs, rhs in
                let lhsWords = lhs.trigger.split(whereSeparator: { $0.isWhitespace }).count
                let rhsWords = rhs.trigger.split(whereSeparator: { $0.isWhitespace }).count
                if lhsWords == rhsWords {
                    return lhs.trigger.count > rhs.trigger.count
                }
                return lhsWords > rhsWords
            }

        var segments: [TextSegment] = [.mutable(text)]
        for replacement in orderedReplacements {
            segments = segments.flatMap { segment in
                switch segment {
                case let .mutable(value):
                    return replace(replacement, in: value)
                case .protected:
                    return [segment]
                }
            }
        }
        return segments
    }

    private func replace(_ replacement: VocabularyReplacement, in text: String) -> [TextSegment] {
        let tokens = replacement.trigger.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else {
            return [.mutable(text)]
        }

        let phrasePattern = tokens
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: #"\s+"#)
        let pattern = #"(?i)(?<![A-Za-z0-9])"# + phrasePattern + #"(?![A-Za-z0-9])"#

        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [.mutable(text)]
        }

        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: nsRange)
        guard !matches.isEmpty else {
            return [.mutable(text)]
        }

        var segments: [TextSegment] = []
        var cursor = text.startIndex

        for match in matches {
            guard let range = Range(match.range, in: text) else {
                continue
            }
            if cursor < range.lowerBound {
                appendMutable(String(text[cursor..<range.lowerBound]), to: &segments)
            }
            segments.append(.protected(replacement.replacement))
            cursor = range.upperBound
        }

        if cursor < text.endIndex {
            appendMutable(String(text[cursor..<text.endIndex]), to: &segments)
        }

        return segments
    }

    private func appendMutable(_ value: String, to segments: inout [TextSegment]) {
        guard !value.isEmpty else {
            return
        }

        if case let .mutable(existing)? = segments.last {
            segments[segments.count - 1] = .mutable(existing + value)
        } else {
            segments.append(.mutable(value))
        }
    }

    private func formatFinalOutput(from segments: [TextSegment]) -> String {
        var sentenceStart = true
        var output = ""

        for segment in segments {
            switch segment {
            case let .mutable(value):
                output += capitalizeMutableText(value, sentenceStart: &sentenceStart)
            case let .protected(value):
                output += value
                updateSentenceState(after: value, sentenceStart: &sentenceStart)
            }
        }

        return output
    }

    private func capitalizeMutableText(_ text: String, sentenceStart: inout Bool) -> String {
        let textWithStandaloneI = text.replacingOccurrences(
            of: #"(?<![A-Za-z0-9])i(?![A-Za-z0-9])"#,
            with: "I",
            options: .regularExpression
        )

        var output = ""
        for character in textWithStandaloneI {
            if sentenceStart, character.isLetter {
                output += String(character).uppercased()
                sentenceStart = false
            } else {
                output.append(character)
                updateSentenceState(after: character, sentenceStart: &sentenceStart)
            }
        }
        return output
    }

    private func updateSentenceState(after text: String, sentenceStart: inout Bool) {
        for character in text {
            updateSentenceState(after: character, sentenceStart: &sentenceStart)
        }
    }

    private func updateSentenceState(after character: Character, sentenceStart: inout Bool) {
        if character == "." || character == "!" || character == "?" || character == "\n" {
            sentenceStart = true
        } else if character.isWhitespace {
            return
        } else if character.isLetter || character.isNumber {
            sentenceStart = false
        }
    }

    private func normalizeSpacing(_ text: String) -> String {
        var output = text
        output = output.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
        output = output.replacingOccurrences(of: #"[ \t]*\n[ \t]*"#, with: "\n", options: .regularExpression)
        output = output.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        output = output.replacingOccurrences(of: #" +([,.;:!?\)\"])"#, with: "$1", options: .regularExpression)
        output = output.replacingOccurrences(of: #"([\(\"]) +"#, with: "$1", options: .regularExpression)
        output = output.replacingOccurrences(of: #"([,.;:!?])([^\s,.;:!?\)\"])"#, with: "$1 $2", options: .regularExpression)
        output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return output
    }
}
