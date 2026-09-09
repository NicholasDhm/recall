import AVFoundation
import Foundation
import Observation
import Speech

/// Transcribes while the microphone is running, from the same buffers the recorder
/// writes to disk. It never downloads a model: if the asset is missing the recording
/// still happens and the pipeline transcribes the file afterwards, with progress shown.
@MainActor
@Observable
final class LiveTranscriber {
    private(set) var finalizedText = ""
    private(set) var volatileText = ""
    private(set) var isRunning = false
    private(set) var unavailableReason: String?

    var displayText: String {
        [finalizedText, volatileText]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private var segments: [TranscribedSegment] = []
    private var analyzer: SpeechAnalyzer?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var feedTask: Task<Void, Never>?
    private var resultsTask: Task<Void, Never>?

    func start(locale: Locale, buffers: AsyncStream<CapturedAudioBuffer>) async {
        reset()

        let resolved: Locale
        do {
            resolved = try await Transcription.prepare(locale: locale, allowDownload: false)
        } catch {
            unavailableReason = error.localizedDescription
            return
        }

        let transcriber = Transcription.liveTranscriber(locale: resolved)
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        ) else {
            unavailableReason = String(localized: "A transcrição ao vivo não está disponível agora.")
            return
        }

        let (inputs, continuation) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .unbounded)
        let analyzer = SpeechAnalyzer(inputSequence: inputs, modules: [transcriber])

        self.analyzer = analyzer
        inputContinuation = continuation
        isRunning = true

        feedTask = Task { [weak self] in
            var converter: AudioBufferConverter?
            var sourceFormat: AVAudioFormat?
            for await captured in buffers {
                if sourceFormat != captured.buffer.format {
                    sourceFormat = captured.buffer.format
                    converter = AudioBufferConverter(from: captured.buffer.format, to: analyzerFormat)
                }
                guard let converted = converter?.convert(captured.buffer) else { continue }
                continuation.yield(AnalyzerInput(buffer: converted))
            }
            continuation.finish()
            _ = self
        }

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self else { return }
                    if result.isFinal {
                        if let segment = TranscriptText.segment(from: result) {
                            self.segments.append(segment)
                        }
                        self.finalizedText = TranscriptText.join(self.segments)
                        self.volatileText = ""
                    } else {
                        self.volatileText = String(result.text.characters)
                    }
                }
            } catch {
                self?.unavailableReason = error.localizedDescription
            }
        }
    }

    /// Stops the analyser and returns what was transcribed, or nil when nothing usable
    /// came out — in which case the caller should leave the recording for the pipeline.
    func finish() async -> TranscriptionOutput? {
        guard isRunning else { return nil }
        isRunning = false

        await feedTask?.value
        inputContinuation?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value

        feedTask = nil
        resultsTask = nil
        analyzer = nil
        inputContinuation = nil
        volatileText = ""

        guard !segments.isEmpty else { return nil }
        return TranscriptionOutput(text: TranscriptText.join(segments), segments: segments)
    }

    func cancel() {
        feedTask?.cancel()
        resultsTask?.cancel()
        inputContinuation?.finish()
        let analyzer = self.analyzer
        Task { await analyzer?.cancelAndFinishNow() }
        reset()
    }

    private func reset() {
        segments = []
        finalizedText = ""
        volatileText = ""
        unavailableReason = nil
        isRunning = false
        analyzer = nil
        inputContinuation = nil
        feedTask = nil
        resultsTask = nil
    }
}
