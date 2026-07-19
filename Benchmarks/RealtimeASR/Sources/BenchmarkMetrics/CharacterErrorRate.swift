import Foundation

public struct CharacterErrorRateScore {
    public let referenceCharacters: Int
    public let hypothesisCharacters: Int
    public let errors: Int

    public var rate: Double {
        guard referenceCharacters > 0 else { return hypothesisCharacters == 0 ? 0 : 1 }
        return Double(errors) / Double(referenceCharacters)
    }
}

public enum CharacterErrorRate {
    public static func score(reference: String, hypothesis: String) -> CharacterErrorRateScore {
        let referenceCharacters = characters(in: reference)
        let hypothesisCharacters = characters(in: hypothesis)
        var previous = Array(0...hypothesisCharacters.count)

        for referenceIndex in referenceCharacters.indices {
            var current = [referenceIndex + 1]
            current.reserveCapacity(hypothesisCharacters.count + 1)
            for hypothesisIndex in hypothesisCharacters.indices {
                let substitution = previous[hypothesisIndex]
                    + (referenceCharacters[referenceIndex] == hypothesisCharacters[hypothesisIndex] ? 0 : 1)
                let insertion = current[hypothesisIndex] + 1
                let deletion = previous[hypothesisIndex + 1] + 1
                current.append(min(substitution, insertion, deletion))
            }
            previous = current
        }

        return CharacterErrorRateScore(
            referenceCharacters: referenceCharacters.count,
            hypothesisCharacters: hypothesisCharacters.count,
            errors: previous.last ?? 0
        )
    }

    private static func characters(in text: String) -> [Character] {
        let normalized = text
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
        return normalized.filter { character in
            character.unicodeScalars.contains {
                CharacterSet.alphanumerics.contains($0)
            }
        }
    }
}
