import Foundation
import Observation
import SwiftData

enum PipelineWork: Sendable, Equatable {
    case transcribe
    case analyze
}

extension Recording.Status {
    /// What the pipeline still owes this recording. `transcribing` and `analyzing` map
    /// back to their own step so a run interrupted by a quit is retried from the start
    /// of that step rather than being stranded.
    var pendingWork: PipelineWork? {
        switch self {
        case .recorded, .transcribing: .transcribe
        case .transcribed, .analyzing: .analyze
        case .ready, .failed: nil
        }
    }

    var label: String {
        switch self {
        case .recorded: String(localized: "Na fila")
        case .transcribing: String(localized: "Transcrevendo")
        case .transcribed: String(localized: "Transcrito")
        case .analyzing: String(localized: "Analisando")
        case .ready: String(localized: "Pronto")
        case .failed: String(localized: "Falhou")
        }
    }
}

/// Drives `recorded → transcribed → ready`, one recording at a time. It is resumable:
/// on launch every recording that still has pending work goes back on the queue.
@MainActor
@Observable
final class RecordingPipeline {
    private(set) var activeRecordingID: UUID?
    private(set) var activeWork: PipelineWork?
    private(set) var downloadProgress: Double?

    private let context: ModelContext
    private let store: AudioStore
    private var worker: Task<Void, Never>?

    init(context: ModelContext, store: AudioStore = .shared) {
        self.context = context
        self.store = store
    }

    var isWorking: Bool { activeRecordingID != nil }

    func resume() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            await self?.drain()
            self?.worker = nil
        }
    }

    /// Puts a failed recording back on the queue from the step it failed at.
    func retry(_ recording: Recording) {
        recording.failureReason = nil
        recording.status = recording.transcriptText.isEmpty ? .recorded : .transcribed
        save()
        resume()
    }

    /// The next recording with outstanding work, oldest first.
    static func next(in recordings: [Recording]) -> Recording? {
        recordings
            .sorted { $0.createdAt < $1.createdAt }
            .first { $0.status.pendingWork != nil }
    }

    /// Runs the queue to exhaustion. `resume` wraps this in a background task; callers
    /// that need to await completion can drive it directly.
    func drain() async {
        while let recording = nextPending() {
            guard let work = recording.status.pendingWork else { break }
            activeRecordingID = recording.id
            activeWork = work
            switch work {
            case .transcribe: await transcribe(recording)
            case .analyze: await analyze(recording)
            }
            activeRecordingID = nil
            activeWork = nil
            downloadProgress = nil
        }
    }

    private func nextPending() -> Recording? {
        let all = (try? context.fetch(FetchDescriptor<Recording>())) ?? []
        return Self.next(in: all)
    }

    private func transcribe(_ recording: Recording) async {
        recording.status = .transcribing
        recording.failureReason = nil
        save()

        let url = store.url(for: recording.audioFileName)
        let locale = Locale(identifier: recording.localeIdentifier)

        do {
            let output = try await Transcription.transcribeFile(at: url, locale: locale) { fraction in
                Task { @MainActor [weak self] in self?.downloadProgress = fraction }
            }
            apply(output, to: recording)
            recording.status = .transcribed
        } catch {
            recording.status = .failed
            recording.failureReason = error.localizedDescription
        }
        downloadProgress = nil
        save()
    }

    private func analyze(_ recording: Recording) async {
        guard !recording.transcriptText.isEmpty else {
            recording.status = .ready
            save()
            return
        }

        // A missing on-device model is not a failure: the recording stays usable.
        if let reason = TranscriptAnalyzer.availability.reason {
            recording.failureReason = reason
            recording.status = .ready
            save()
            return
        }

        recording.status = .analyzing
        recording.failureReason = nil
        save()

        do {
            let segments = recording.segments
                .sorted { $0.start < $1.start }
                .map { TranscribedSegment(start: $0.start, end: $0.end, text: $0.text) }
            let result = try await TranscriptAnalyzer.analyze(
                transcript: recording.transcriptText,
                segments: segments
            )
            recording.summary = result.summary.isEmpty ? nil : result.summary
            recording.tags = result.tags
            recording.actionItems = result.actionItems
        } catch {
            recording.failureReason = error.localizedDescription
        }

        recording.status = .ready
        save()
    }

    /// Throws the analysis away and runs it again from the existing transcript.
    func reanalyze(_ recording: Recording) {
        guard !recording.transcriptText.isEmpty else { return }
        recording.summary = nil
        recording.tags = []
        recording.actionItems = []
        recording.failureReason = nil
        recording.status = .transcribed
        save()
        resume()
    }

    func apply(_ output: TranscriptionOutput, to recording: Recording) {
        recording.transcriptText = output.text
        recording.wordCount = output.wordCount
        for segment in recording.segments {
            context.delete(segment)
        }
        recording.segments = output.segments.map {
            TranscriptSegment(start: $0.start, end: $0.end, text: $0.text)
        }
    }

    private func save() {
        try? context.save()
    }
}
