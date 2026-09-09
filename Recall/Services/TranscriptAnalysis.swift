import Foundation
import FoundationModels

@Generable
struct TranscriptAnalysis {
    @Guide(description: "Resumo de 2 a 4 frases, em português do Brasil")
    var summary: String

    @Guide(description: "De 3 a 5 tags curtas em minúsculas, sem #", .count(3...5))
    var tags: [String]

    @Guide(description: "Itens de ação explícitos no texto; lista vazia se não houver")
    var actionItems: [String]
}

struct AnalysisResult: Sendable, Equatable {
    var summary: String
    var tags: [String]
    var actionItems: [String]

    static let empty = AnalysisResult(summary: "", tags: [], actionItems: [])
}

extension TranscriptAnalysis {
    var result: AnalysisResult {
        AnalysisResult(
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: TagNormalizer.normalize(tags),
            actionItems: ListNormalizer.normalize(actionItems)
        )
    }
}

enum TagNormalizer {
    static let limit = 5

    /// Lower-cased, `#`-free, de-duplicated, order preserved, capped at `limit`.
    static func normalize(_ tags: [String], limit: Int = limit) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tag in tags {
            let cleaned = tag
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
            guard !cleaned.isEmpty, seen.insert(cleaned).inserted else { continue }
            result.append(cleaned)
            if result.count == limit { break }
        }
        return result
    }
}

enum ListNormalizer {
    /// Trims, drops empties and de-duplicates case-insensitively, preserving order.
    static func normalize(_ items: [String], limit: Int = 20) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for item in items {
            let cleaned = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, seen.insert(cleaned.lowercased()).inserted else { continue }
            result.append(cleaned)
            if result.count == limit { break }
        }
        return result
    }
}

enum TranscriptChunker {
    /// The on-device window is small; 2 500 words leaves room for the instructions
    /// and the structured response.
    static let maxWords = 2_500

    static func chunks(from segments: [TranscribedSegment], maxWords: Int = maxWords) -> [String] {
        chunks(ofPieces: segments.map(\.text), maxWords: maxWords)
    }

    static func chunks(from text: String, maxWords: Int = maxWords) -> [String] {
        chunks(ofPieces: sentences(of: text), maxWords: maxWords)
    }

    /// Groups whole pieces in order, never splitting one. A piece longer than
    /// `maxWords` becomes a chunk of its own rather than being dropped.
    static func chunks(ofPieces pieces: [String], maxWords: Int) -> [String] {
        var chunks: [String] = []
        var current: [String] = []
        var currentWords = 0

        for piece in pieces {
            let trimmed = piece.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let words = TranscriptText.wordCount(trimmed)
            if currentWords > 0, currentWords + words > maxWords {
                chunks.append(current.joined(separator: " "))
                current = []
                currentWords = 0
            }
            current.append(trimmed)
            currentWords += words
        }

        if !current.isEmpty {
            chunks.append(current.joined(separator: " "))
        }
        return chunks
    }

    static func sentences(of text: String) -> [String] {
        var result: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: [.bySentences, .localized]) { substring, _, _, _ in
            if let substring, !substring.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                result.append(substring.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return result.isEmpty ? [text] : result
    }
}

extension AnalysisResult {
    /// Deterministic merge of per-chunk analyses, used as the consolidation pass and as
    /// the fallback when the model cannot do the final pass itself.
    static func merge(_ parts: [AnalysisResult]) -> AnalysisResult {
        AnalysisResult(
            summary: parts
                .map(\.summary)
                .filter { !$0.isEmpty }
                .joined(separator: " "),
            tags: TagNormalizer.normalize(parts.flatMap(\.tags)),
            actionItems: ListNormalizer.normalize(parts.flatMap(\.actionItems))
        )
    }
}
