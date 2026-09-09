import Foundation
import SwiftData
import Testing

@testable import Recall

@Suite("Tags and lists")
struct TagNormalizerTests {
    @Test("Tags come back lower-cased, without hashes, and de-duplicated")
    func normalize() {
        let tags = TagNormalizer.normalize(["#Reunião", "reunião", " PRODUTO ", "", "  ", "#produto"])
        #expect(tags == ["reunião", "produto"])
    }

    @Test("Tags keep the order they arrived in and stop at the limit")
    func orderAndLimit() {
        let tags = TagNormalizer.normalize(["um", "dois", "três", "quatro", "cinco", "seis"])
        #expect(tags == ["um", "dois", "três", "quatro", "cinco"])
    }

    @Test("Inner whitespace collapses to single spaces")
    func collapsesWhitespace() {
        #expect(TagNormalizer.normalize(["planejamento   anual"]) == ["planejamento anual"])
    }

    @Test("Action items de-duplicate case-insensitively and keep their casing")
    func actionItems() {
        let items = ListNormalizer.normalize([" Enviar o relatório ", "enviar o relatório", "", "Marcar reunião"])
        #expect(items == ["Enviar o relatório", "Marcar reunião"])
    }
}

@Suite("Transcript chunking")
struct TranscriptChunkerTests {
    private func segments(_ texts: [String]) -> [TranscribedSegment] {
        texts.enumerated().map {
            TranscribedSegment(start: Double($0.offset), end: Double($0.offset + 1), text: $0.element)
        }
    }

    @Test("Nothing in, nothing out")
    func empty() {
        #expect(TranscriptChunker.chunks(from: [TranscribedSegment]()).isEmpty)
        #expect(TranscriptChunker.chunks(ofPieces: ["", "   "], maxWords: 10).isEmpty)
    }

    @Test("A short transcript is a single chunk")
    func singleChunk() {
        let chunks = TranscriptChunker.chunks(from: segments(["Bom dia.", "Vamos começar."]))
        #expect(chunks == ["Bom dia. Vamos começar."])
    }

    @Test("Chunks stay under the word limit and never split a segment")
    func respectsLimit() {
        let pieces = ["um dois três", "quatro cinco seis", "sete oito nove", "dez"]
        let chunks = TranscriptChunker.chunks(ofPieces: pieces, maxWords: 5)

        #expect(chunks == ["um dois três", "quatro cinco seis", "sete oito nove dez"])
        for chunk in chunks {
            #expect(TranscriptText.wordCount(chunk) <= 5)
        }
    }

    @Test("Order is preserved and no words are lost")
    func preservesOrderAndContent() {
        let pieces = (1...20).map { "trecho número \($0)" }
        let chunks = TranscriptChunker.chunks(ofPieces: pieces, maxWords: 7)

        #expect(chunks.count > 1)
        #expect(chunks.joined(separator: " ") == pieces.joined(separator: " "))
        #expect(chunks.first?.hasPrefix("trecho número 1") == true)
        #expect(chunks.last?.hasSuffix("trecho número 20") == true)
    }

    @Test("A single oversized segment becomes its own chunk instead of being dropped")
    func oversizedPiece() {
        let long = (1...50).map(String.init).joined(separator: " ")
        let chunks = TranscriptChunker.chunks(ofPieces: ["curto", long, "fim"], maxWords: 5)

        #expect(chunks.contains(long))
        #expect(chunks.first == "curto")
        #expect(chunks.last == "fim")
    }

    @Test("A transcript without segments is split on sentence boundaries")
    func plainTextFallback() {
        let text = "Primeira frase. Segunda frase! Terceira frase?"
        let chunks = TranscriptChunker.chunks(from: text, maxWords: 2)

        #expect(chunks.count == 3)
        #expect(chunks[0].hasPrefix("Primeira"))
        #expect(chunks[2].hasPrefix("Terceira"))
    }
}

@Suite("Analysis consolidation")
struct AnalysisConsolidationTests {
    @Test("Merging joins the summaries in order")
    func mergeSummaries() {
        let merged = AnalysisResult.merge([
            AnalysisResult(summary: "Parte um.", tags: [], actionItems: []),
            AnalysisResult(summary: "", tags: [], actionItems: []),
            AnalysisResult(summary: "Parte dois.", tags: [], actionItems: [])
        ])
        #expect(merged.summary == "Parte um. Parte dois.")
    }

    @Test("Merging unions the tags, normalising and capping them")
    func mergeTags() {
        let merged = AnalysisResult.merge([
            AnalysisResult(summary: "", tags: ["#Produto", "vendas"], actionItems: []),
            AnalysisResult(summary: "", tags: ["produto", "Marketing", "suporte", "rh", "financeiro"], actionItems: [])
        ])
        #expect(merged.tags == ["produto", "vendas", "marketing", "suporte", "rh"])
    }

    @Test("Merging de-duplicates the action items across chunks")
    func mergeActionItems() {
        let merged = AnalysisResult.merge([
            AnalysisResult(summary: "", tags: [], actionItems: ["Enviar o relatório"]),
            AnalysisResult(summary: "", tags: [], actionItems: ["enviar o relatório", "Agendar a call"])
        ])
        #expect(merged.actionItems == ["Enviar o relatório", "Agendar a call"])
    }

    @Test("Merging nothing yields the empty result")
    func mergeEmpty() {
        #expect(AnalysisResult.merge([]) == .empty)
    }
}

@MainActor
@Suite("Analysis fallback")
struct AnalysisFallbackTests {
    @Test("Unavailability always carries a readable reason")
    func availabilityReason() {
        switch TranscriptAnalyzer.availability {
        case .available:
            #expect(TranscriptAnalyzer.availability.reason == nil)
        case .unavailable(let reason):
            #expect(!reason.isEmpty)
        }
    }

    @Test("The pipeline reaches .ready whether or not the model is available")
    func pipelineAlwaysFinishes() async throws {
        let context = ModelContext(try RecallModelContainer.make(inMemory: true))
        let pipeline = RecordingPipeline(context: context)

        let withTranscript = Recording(
            title: "Com texto",
            duration: 30,
            audioFileName: "a.m4a",
            localeIdentifier: "pt-BR",
            source: .microphone,
            status: .transcribed
        )
        withTranscript.transcriptText = "Precisamos enviar o relatório na sexta e agendar a próxima reunião."

        let withoutTranscript = Recording(
            title: "Sem texto",
            duration: 5,
            audioFileName: "b.m4a",
            localeIdentifier: "pt-BR",
            source: .microphone,
            status: .transcribed
        )

        context.insert(withTranscript)
        context.insert(withoutTranscript)
        try context.save()

        await pipeline.drain()

        #expect(withTranscript.status == .ready)
        #expect(withoutTranscript.status == .ready)
        // Without the model there is no summary, and that is not an error state.
        if TranscriptAnalyzer.availability != .available {
            #expect(withTranscript.summary == nil)
            #expect(withTranscript.failureReason?.isEmpty == false)
        }
    }

    @Test("Reanalysing clears the previous result and requeues the recording")
    func reanalyzeRequeues() throws {
        let context = ModelContext(try RecallModelContainer.make(inMemory: true))
        let pipeline = RecordingPipeline(context: context)

        let recording = Recording(
            title: "Gravação",
            duration: 60,
            audioFileName: "c.m4a",
            localeIdentifier: "pt-BR",
            source: .microphone,
            status: .ready
        )
        recording.transcriptText = "Texto qualquer."
        recording.summary = "Resumo antigo."
        recording.tags = ["antigo"]
        recording.actionItems = ["Item antigo"]
        context.insert(recording)
        try context.save()

        pipeline.reanalyze(recording)

        #expect(recording.summary == nil)
        #expect(recording.tags.isEmpty)
        #expect(recording.actionItems.isEmpty)
        #expect(recording.status.pendingWork == .analyze)
    }

    @Test("Reanalysing a recording with no transcript does nothing")
    func reanalyzeWithoutTranscript() throws {
        let context = ModelContext(try RecallModelContainer.make(inMemory: true))
        let pipeline = RecordingPipeline(context: context)

        let recording = Recording(
            title: "Vazia",
            duration: 3,
            audioFileName: "d.m4a",
            localeIdentifier: "pt-BR",
            source: .microphone,
            status: .ready
        )
        context.insert(recording)
        pipeline.reanalyze(recording)

        #expect(recording.status == .ready)
    }
}
