import Foundation
import Testing

@testable import Recall

/// Exercises the real on-device model. Skipped where Apple Intelligence is unavailable,
/// so the suite still passes on an ineligible device.
@Suite("Analyzer against the on-device model", .serialized)
struct AnalyzerIntegrationTests {
    private let transcript = """
    Bom dia pessoal, obrigado por virem. Hoje quero fechar o escopo do lançamento do \
    aplicativo. A gente combinou que o Pedro vai enviar o relatório de custos até \
    sexta-feira. A Ana precisa agendar a reunião com o time de marketing na próxima \
    semana. O orçamento aprovado ficou em trinta mil reais e não pode passar disso. \
    Sobre o prazo, a data de lançamento continua sendo o dia quinze do mês que vem.
    """

    private func segments(from text: String, perSegment: Int = 12) -> [TranscribedSegment] {
        let words = text.split(separator: " ").map(String.init)
        return stride(from: 0, to: words.count, by: perSegment).enumerated().map { index, start in
            TranscribedSegment(
                start: Double(index * 5),
                end: Double((index + 1) * 5),
                text: words[start..<min(start + perSegment, words.count)].joined(separator: " ")
            )
        }
    }

    @Test("A single-chunk transcript yields a summary and well-formed tags")
    func singleChunk() async throws {
        try #require(TranscriptAnalyzer.availability == .available, "Apple Intelligence unavailable here")

        let result = try await TranscriptAnalyzer.analyze(
            transcript: transcript,
            segments: segments(from: transcript)
        )

        #expect(!result.summary.isEmpty)
        #expect((3...5).contains(result.tags.count))
        #expect(result.tags.allSatisfy { $0 == $0.lowercased() })
        #expect(result.tags.allSatisfy { !$0.contains("#") })
        #expect(Set(result.tags).count == result.tags.count)
        #expect(result.actionItems.allSatisfy { !$0.isEmpty })
    }

    @Test("A transcript split across chunks still consolidates into one result")
    func multipleChunksConsolidate() async throws {
        try #require(TranscriptAnalyzer.availability == .available, "Apple Intelligence unavailable here")

        let parts = segments(from: transcript)
        let chunks = TranscriptChunker.chunks(from: parts, maxWords: 30)
        try #require(chunks.count > 1, "the fixture must span more than one chunk")

        let result = try await TranscriptAnalyzer.analyze(
            transcript: transcript,
            segments: parts,
            maxWords: 30
        )

        #expect(!result.summary.isEmpty)
        #expect(result.tags.count <= TagNormalizer.limit)
        #expect(Set(result.tags).count == result.tags.count)
        #expect(result.tags.allSatisfy { $0 == $0.lowercased() })
    }
}
