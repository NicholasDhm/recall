import Foundation
import FoundationModels

enum ModelAvailability: Sendable, Equatable {
    case available
    case unavailable(String)

    var reason: String? {
        if case .unavailable(let reason) = self { return reason }
        return nil
    }
}

/// Summarises a transcript with the on-device model. Everything here is optional to the
/// app: when the model is missing the pipeline still finishes and the recording is usable.
enum TranscriptAnalyzer {
    static var availability: ModelAvailability {
        switch SystemLanguageModel.default.availability {
        case .available:
            .available
        case .unavailable(.deviceNotEligible):
            .unavailable(String(localized: "Este aparelho não é compatível com o Apple Intelligence."))
        case .unavailable(.appleIntelligenceNotEnabled):
            .unavailable(String(localized: "Ative o Apple Intelligence nos Ajustes do iPhone para gerar resumos."))
        case .unavailable(.modelNotReady):
            .unavailable(String(localized: "O modelo do Apple Intelligence ainda está sendo preparado. Tente de novo mais tarde."))
        case .unavailable:
            .unavailable(String(localized: "O Apple Intelligence não está disponível agora."))
        }
    }

    private static let instructions = """
    Você analisa transcrições de áudio em português do Brasil.
    Responda sempre em português do Brasil, de forma objetiva e sem inventar informação
    que não esteja na transcrição. Se a transcrição não tiver itens de ação, devolva uma
    lista vazia.
    """

    static func analyze(
        transcript: String,
        segments: [TranscribedSegment],
        maxWords: Int = TranscriptChunker.maxWords
    ) async throws -> AnalysisResult {
        let chunks = segments.isEmpty
            ? TranscriptChunker.chunks(from: transcript, maxWords: maxWords)
            : TranscriptChunker.chunks(from: segments, maxWords: maxWords)
        guard !chunks.isEmpty else { return .empty }

        var parts: [AnalysisResult] = []
        for chunk in chunks {
            parts.append(try await analyze(chunk: chunk, of: chunks.count))
        }

        guard parts.count > 1 else { return parts[0] }
        return await consolidate(parts)
    }

    private static func analyze(chunk: String, of total: Int) async throws -> AnalysisResult {
        let session = LanguageModelSession(instructions: instructions)
        let scope = total > 1
            ? "Este é um trecho de uma transcrição maior."
            : "Esta é a transcrição completa."
        let response = try await session.respond(
            to: """
            \(scope)
            Resuma o conteúdo, proponha tags e liste os itens de ação.

            Transcrição:
            \(chunk)
            """,
            generating: TranscriptAnalysis.self
        )
        return response.content.result
    }

    /// Final pass over the per-chunk summaries. Falls back to the deterministic merge
    /// when the model cannot produce one.
    private static func consolidate(_ parts: [AnalysisResult]) async -> AnalysisResult {
        let merged = AnalysisResult.merge(parts)
        let session = LanguageModelSession(instructions: instructions)
        let joined = parts.enumerated()
            .map { "Trecho \($0.offset + 1): \($0.element.summary)" }
            .joined(separator: "\n")

        do {
            let response = try await session.respond(
                to: """
                Abaixo estão os resumos dos trechos de uma mesma gravação, em ordem.
                Escreva um único resumo do todo, escolha as tags mais representativas e
                reúna os itens de ação sem repetir.

                \(joined)

                Itens de ação já encontrados:
                \(merged.actionItems.map { "- \($0)" }.joined(separator: "\n"))
                """,
                generating: TranscriptAnalysis.self
            )
            let consolidated = response.content.result
            return consolidated.summary.isEmpty ? merged : consolidated
        } catch {
            return merged
        }
    }
}
