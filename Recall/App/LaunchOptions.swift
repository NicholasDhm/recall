#if DEBUG
import AVFoundation
import Foundation
import SwiftData

/// Debug-only launch switches used to drive the simulator for screenshots and manual
/// checks. Compiled out of release builds.
///
///     xcrun simctl launch booted com.nickdhm.recall -recall-fixtures -recall-tab insights
enum LaunchOptions {
    static var seedsFixtures: Bool {
        ProcessInfo.processInfo.arguments.contains("-recall-fixtures")
    }

    static var initialTab: RootTab? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-recall-tab"),
              let name = arguments[safe: index + 1] else { return nil }
        switch name {
        case "record": return .record
        case "library": return .library
        case "insights": return .insights
        case "settings": return .settings
        default: return nil
        }
    }

    /// Starts a recording as soon as the Gravar tab appears, so the recording state
    /// itself can be screenshotted from the command line.
    static var autoRecord: Bool {
        ProcessInfo.processInfo.arguments.contains("-recall-autorecord")
    }

    /// Opens the newest recording on the Biblioteca tab, for screenshots.
    static var opensFirstRecording: Bool {
        ProcessInfo.processInfo.arguments.contains("-recall-open-first")
    }

    /// Section anchor the Insights tab scrolls to on appear, for screenshots.
    static var insightsAnchor: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-recall-scroll-to") else { return nil }
        return arguments[safe: index + 1]
    }

    @MainActor
    static func seedFixtures(into context: ModelContext, store: AudioStore = .shared) {
        RecordingActions.deleteAll(in: context, store: store)
        try? store.createDirectoryIfNeeded()

        for fixture in fixtures {
            let id = UUID()
            let fileName = store.makeFileName(id: id)
            writeTone(to: store.url(for: fileName), seconds: min(fixture.duration, 6))

            let recording = Recording(
                id: id,
                createdAt: fixture.createdAt,
                title: fixture.title,
                duration: fixture.duration,
                audioFileName: fileName,
                localeIdentifier: "pt-BR",
                source: fixture.source,
                status: .ready
            )
            recording.transcriptText = fixture.transcript
            recording.wordCount = fixture.wordCount
            recording.summary = fixture.summary
            recording.tags = fixture.tags
            recording.actionItems = fixture.actionItems
            recording.segments = fixture.segments()
            context.insert(recording)
        }
        try? context.save()
    }

    private struct Fixture {
        var daysAgo: Int
        var hour: Int
        var title: String
        var duration: TimeInterval
        var source: Recording.Source
        var summary: String
        var tags: [String]
        var actionItems: [String]
        /// Words in the full recording. The `transcript` below is only an excerpt, so
        /// the words-per-minute chart would read far too low if it were counted.
        var wordCount: Int
        var transcript: String

        var createdAt: Date {
            let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
            return Calendar.current.date(bySettingHour: hour, minute: 12, second: 0, of: day)!
        }

        /// Splits the transcript into sentence-sized segments spread across the duration.
        func segments() -> [TranscriptSegment] {
            let sentences = TranscriptChunker.sentences(of: transcript)
            let step = duration / Double(max(sentences.count, 1))
            return sentences.enumerated().map { index, text in
                TranscriptSegment(
                    start: Double(index) * step,
                    end: Double(index + 1) * step,
                    text: text
                )
            }
        }
    }

    private static let fixtures: [Fixture] = [
        Fixture(
            daysAgo: 0,
            hour: 9,
            title: "Planejamento da semana",
            duration: 8 * 60 + 40,
            source: .microphone,
            summary: "Revisão das prioridades da semana e divisão das tarefas entre o time. O prazo do lançamento continua de pé.",
            tags: ["planejamento", "time", "lançamento"],
            actionItems: ["Enviar o cronograma revisado até quarta", "Confirmar a data com o time de marketing"],
            wordCount: 1_120,
            transcript: "Bom dia pessoal, vamos revisar as prioridades da semana. O relatório de custos precisa sair até quarta-feira. A Ana fica responsável pelo contato com marketing. O prazo do lançamento continua sendo o dia quinze. Nenhuma mudança no orçamento por enquanto."
        ),
        Fixture(
            daysAgo: 1,
            hour: 18,
            title: "Notas rápidas do dia",
            duration: 2 * 60 + 15,
            source: .microphone,
            summary: "Anotações soltas sobre o andamento do projeto e uma ideia para simplificar o cadastro.",
            tags: ["notas", "produto"],
            actionItems: ["Testar o fluxo de cadastro simplificado"],
            wordCount: 290,
            transcript: "Uma ideia rápida antes de esquecer. O cadastro está longo demais. Dá para juntar as duas primeiras telas numa só. Isso reduz o abandono no início do fluxo do produto."
        ),
        Fixture(
            daysAgo: 3,
            hour: 14,
            title: "Reunião com o cliente",
            duration: 27 * 60 + 5,
            source: .microphone,
            summary: "O cliente aprovou o escopo e pediu ajustes no relatório mensal. Ficou combinado um novo ponto de contato quinzenal.",
            tags: ["cliente", "reunião", "escopo"],
            actionItems: ["Ajustar o relatório mensal", "Agendar o ponto quinzenal"],
            wordCount: 3_460,
            transcript: "Obrigado pelo tempo de vocês. O escopo que enviamos foi aprovado sem alterações. O único pedido é ajustar o relatório mensal para incluir a quebra por região. Vamos marcar um ponto quinzenal para acompanhar o andamento. O orçamento segue o que foi combinado no contrato."
        ),
        Fixture(
            daysAgo: 8,
            hour: 11,
            title: "Entrevista importada",
            duration: 41 * 60 + 30,
            source: .imported,
            summary: "Entrevista sobre hábitos de uso do aplicativo. O entrevistado destacou a busca e a exportação como pontos fortes.",
            tags: ["pesquisa", "entrevista", "produto"],
            actionItems: ["Compilar as citações para o relatório de pesquisa"],
            wordCount: 5_240,
            transcript: "Eu uso o aplicativo quase todo dia no trabalho. A busca é o que mais me ajuda, porque encontro qualquer coisa rápido. A exportação também é útil quando preciso mandar para o time. O que me incomoda é a organização das pastas. Fora isso o produto atende bem."
        ),
        Fixture(
            daysAgo: 16,
            hour: 20,
            title: "Ideias para o próximo trimestre",
            duration: 12 * 60 + 50,
            source: .microphone,
            summary: "Lista de ideias para o trimestre seguinte, com foco em pesquisa com usuários e melhorias de desempenho.",
            tags: ["planejamento", "produto", "pesquisa"],
            actionItems: ["Escolher três ideias para validar"],
            wordCount: 1_640,
            transcript: "Algumas ideias para o próximo trimestre. Primeiro, mais pesquisa com usuários reais. Segundo, melhorar o desempenho da tela inicial. Terceiro, revisar a organização das pastas que apareceu na entrevista. Precisamos escolher três para validar antes de começar."
        )
    ]

    /// A short quiet tone so the player and the scrubber have real audio to work with.
    private static func writeTone(to url: URL, seconds: TimeInterval) {
        try? FileManager.default.removeItem(at: url)
        guard let file = try? AVAudioFile(forWriting: url, settings: AudioFormat.settings) else { return }
        let frames = AVAudioFrameCount(AudioFormat.sampleRate * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = frames
        for index in 0..<Int(frames) {
            samples[index] = 0.05 * sin(2 * .pi * 220 * Float(index) / Float(AudioFormat.sampleRate))
        }
        try? file.write(from: buffer)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
#endif
