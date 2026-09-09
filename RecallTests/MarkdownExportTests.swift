import Foundation
import Testing

@testable import Recall

@Suite("Markdown export")
struct MarkdownExportTests {
    private let createdAt = DateComponents(
        calendar: Calendar(identifier: .gregorian),
        timeZone: TimeZone(identifier: "America/Sao_Paulo"),
        year: 2026, month: 3, day: 18, hour: 9, minute: 30
    ).date!

    private func export(
        summary: String? = "Alinhamento do lançamento.",
        tags: [String] = ["reunião", "produto"],
        actionItems: [String] = ["Enviar o relatório"],
        segments: [TranscribedSegment] = [
            TranscribedSegment(start: 0, end: 65, text: "Bom dia pessoal."),
            TranscribedSegment(start: 65, end: 130, text: "Vamos revisar as prioridades.")
        ],
        transcriptText: String = "Bom dia pessoal. Vamos revisar as prioridades.",
        title: String = "Planejamento da semana"
    ) -> MarkdownExport {
        MarkdownExport.make(
            title: title,
            createdAt: createdAt,
            duration: 130,
            summary: summary,
            tags: tags,
            actionItems: actionItems,
            segments: segments,
            transcriptText: transcriptText
        )
    }

    @Test("The document carries title, date, summary, action items and transcript")
    func fullDocument() {
        let text = export().text

        #expect(text.hasPrefix("# Planejamento da semana"))
        #expect(text.contains("2:10"))
        #expect(text.contains("#reunião #produto"))
        #expect(text.contains("## Resumo"))
        #expect(text.contains("Alinhamento do lançamento."))
        #expect(text.contains("## Itens de ação"))
        #expect(text.contains("- [ ] Enviar o relatório"))
        #expect(text.contains("## Transcrição"))
        #expect(text.contains("**0:00** Bom dia pessoal."))
        #expect(text.contains("**1:05** Vamos revisar as prioridades."))
    }

    @Test("Sections with nothing in them are left out")
    func omitsEmptySections() {
        let text = export(summary: nil, tags: [], actionItems: []).text

        #expect(!text.contains("## Resumo"))
        #expect(!text.contains("## Itens de ação"))
        #expect(text.contains("## Transcrição"))
    }

    @Test("Without segments the plain transcript is used")
    func fallsBackToPlainTranscript() {
        let text = export(segments: []).text
        #expect(text.contains("Bom dia pessoal. Vamos revisar as prioridades."))
        #expect(!text.contains("**0:00**"))
    }

    @Test("A recording with no transcript still exports")
    func emptyTranscript() {
        let text = export(summary: nil, tags: [], actionItems: [], segments: [], transcriptText: "").text
        #expect(text.contains("_Sem transcrição._"))
    }

    @Test("The suggested file name is safe for a file system")
    func fileName() {
        #expect(export().fileName == "Planejamento da semana.md")
        #expect(export(title: "Reunião 12/03: revisão").fileName == "Reunião 12-03- revisão.md")
        #expect(export(title: "   ").fileName == "Gravação.md")
    }
}
