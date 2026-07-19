import Foundation

public struct WordErrorRateScore {
    public let referenceWords: Int
    public let hypothesisWords: Int
    public let substitutions: Int
    public let insertions: Int
    public let deletions: Int

    public var errors: Int {
        substitutions + insertions + deletions
    }

    public var rate: Double {
        guard referenceWords > 0 else { return hypothesisWords == 0 ? 0 : 1 }
        return Double(errors) / Double(referenceWords)
    }
}

public enum WordErrorRate {
    public static func score(reference: String, hypothesis: String) -> WordErrorRateScore {
        let referenceWords = words(in: reference)
        let hypothesisWords = words(in: hypothesis)

        struct Cell {
            var total: Int
            var substitutions: Int
            var insertions: Int
            var deletions: Int
        }

        var matrix = Array(
            repeating: Array(
                repeating: Cell(total: 0, substitutions: 0, insertions: 0, deletions: 0),
                count: hypothesisWords.count + 1
            ),
            count: referenceWords.count + 1
        )
        if !referenceWords.isEmpty {
            for index in 1...referenceWords.count {
                matrix[index][0] = Cell(total: index, substitutions: 0, insertions: 0, deletions: index)
            }
        }
        if !hypothesisWords.isEmpty {
            for index in 1...hypothesisWords.count {
                matrix[0][index] = Cell(total: index, substitutions: 0, insertions: index, deletions: 0)
            }
        }

        if !referenceWords.isEmpty, !hypothesisWords.isEmpty {
            for referenceIndex in 1...referenceWords.count {
                for hypothesisIndex in 1...hypothesisWords.count {
                    if referenceWords[referenceIndex - 1] == hypothesisWords[hypothesisIndex - 1] {
                        matrix[referenceIndex][hypothesisIndex] = matrix[referenceIndex - 1][hypothesisIndex - 1]
                        continue
                    }

                    var substitution = matrix[referenceIndex - 1][hypothesisIndex - 1]
                    substitution.total += 1
                    substitution.substitutions += 1

                    var insertion = matrix[referenceIndex][hypothesisIndex - 1]
                    insertion.total += 1
                    insertion.insertions += 1

                    var deletion = matrix[referenceIndex - 1][hypothesisIndex]
                    deletion.total += 1
                    deletion.deletions += 1

                    matrix[referenceIndex][hypothesisIndex] = [substitution, insertion, deletion]
                        .min { lhs, rhs in
                            if lhs.total != rhs.total { return lhs.total < rhs.total }
                            if lhs.substitutions != rhs.substitutions {
                                return lhs.substitutions < rhs.substitutions
                            }
                            return lhs.deletions < rhs.deletions
                        }!
                }
            }
        }

        let final = matrix[referenceWords.count][hypothesisWords.count]
        return WordErrorRateScore(
            referenceWords: referenceWords.count,
            hypothesisWords: hypothesisWords.count,
            substitutions: final.substitutions,
            insertions: final.insertions,
            deletions: final.deletions
        )
    }

    private static func words(in text: String) -> [String] {
        let normalized = text
            .folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .replacingOccurrences(
                of: "[^\\p{L}\\p{N}]+",
                with: " ",
                options: .regularExpression
            )
        return normalized.split(whereSeparator: { $0 == " " }).map(String.init)
    }
}
