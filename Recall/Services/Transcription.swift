import AVFoundation
import CoreMedia
import Foundation
import Speech

struct TranscribedSegment: Sendable, Equatable {
    var start: TimeInterval
    var end: TimeInterval
    var text: String
}

struct TranscriptionOutput: Sendable, Equatable {
    var text: String
    var segments: [TranscribedSegment]

    var wordCount: Int { TranscriptText.wordCount(text) }
}

enum TranscriptionError: LocalizedError {
    case unavailableOnThisDevice
    case localeUnsupported(String)
    case modelMissing(String)

    var errorDescription: String? {
        switch self {
        case .unavailableOnThisDevice:
            String(localized: "A transcrição no aparelho não está disponível aqui. Ela funciona em um iPhone com iOS 26, não no simulador.")
        case .localeUnsupported(let identifier):
            String(localized: "O idioma \(identifier) não é suportado pela transcrição deste iPhone.")
        case .modelMissing(let identifier):
            String(localized: "O modelo de fala para \(identifier) ainda não foi baixado.")
        }
    }
}

enum TranscriptText {
    /// Tokens that carry at least one letter or digit — bare punctuation does not count.
    static func wordCount(_ text: String) -> Int {
        text
            .split(whereSeparator: \.isWhitespace)
            .count { $0.contains(where: { $0.isLetter || $0.isNumber }) }
    }

    static func join(_ segments: [TranscribedSegment]) -> String {
        segments
            .map(\.text)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Builds a segment from one finalised transcriber result, dropping results with
    /// no usable time range or no text.
    static func segment(from result: SpeechTranscriber.Result) -> TranscribedSegment? {
        let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let start = result.range.start
        let end = result.range.end
        guard start.isNumeric, end.isNumeric else { return nil }
        return TranscribedSegment(
            start: max(0, start.seconds),
            end: max(start.seconds, end.seconds),
            text: text
        )
    }
}

enum Transcription {
    /// Final results only, with per-result time ranges.
    static func fileTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )
    }

    /// Adds volatile results so text appears while the user is still speaking.
    static func liveTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
    }

    /// Resolves the locale and makes sure its model is on the device.
    static func prepare(
        locale: Locale,
        allowDownload: Bool,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Locale {
        guard SpeechTranscriber.isAvailable else {
            throw TranscriptionError.unavailableOnThisDevice
        }
        guard let resolved = await SpeechAssets.resolve(locale) else {
            throw TranscriptionError.localeUnsupported(locale.identifier)
        }

        switch await SpeechAssets.status(for: resolved) {
        case .installed:
            return resolved
        case .unsupported:
            throw TranscriptionError.localeUnsupported(resolved.identifier)
        default:
            guard allowDownload else {
                throw TranscriptionError.modelMissing(resolved.identifier)
            }
            try await SpeechAssets.install(resolved, progress: progress)
            await SpeechAssets.reserve(resolved)
            return resolved
        }
    }

    static func transcribeFile(
        at url: URL,
        locale: Locale,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> TranscriptionOutput {
        let resolved = try await prepare(locale: locale, allowDownload: true, progress: progress)
        let transcriber = fileTranscriber(locale: resolved)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: url)

        let collector = Task { try await collect(transcriber.results) }
        do {
            _ = try await analyzer.analyzeSequence(from: file)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            collector.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }

        let segments = try await collector.value
        return TranscriptionOutput(text: TranscriptText.join(segments), segments: segments)
    }

    private static func collect<Results: AsyncSequence & Sendable>(
        _ results: Results
    ) async throws -> [TranscribedSegment] where Results.Element == SpeechTranscriber.Result {
        var segments: [TranscribedSegment] = []
        for try await result in results where result.isFinal {
            if let segment = TranscriptText.segment(from: result) {
                segments.append(segment)
            }
        }
        return segments
    }
}
