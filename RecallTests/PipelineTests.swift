import Foundation
import SwiftData
import Testing

@testable import Recall

@MainActor
@Suite("Pipeline queue")
struct PipelineQueueTests {
    private func makeRecording(_ status: Recording.Status, createdAt: Date = .now) -> Recording {
        let recording = Recording(
            createdAt: createdAt,
            title: "Gravação",
            duration: 10,
            audioFileName: "\(UUID().uuidString).m4a",
            localeIdentifier: "pt-BR",
            source: .microphone,
            status: status
        )
        return recording
    }

    @Test("Every status maps to the step the pipeline still owes it")
    func pendingWorkPerStatus() {
        #expect(Recording.Status.recorded.pendingWork == .transcribe)
        // An interrupted run restarts its own step rather than being stranded.
        #expect(Recording.Status.transcribing.pendingWork == .transcribe)
        #expect(Recording.Status.transcribed.pendingWork == .analyze)
        #expect(Recording.Status.analyzing.pendingWork == .analyze)
        #expect(Recording.Status.ready.pendingWork == nil)
        #expect(Recording.Status.failed.pendingWork == nil)
    }

    @Test("The queue picks up work left behind in any interrupted status")
    func queueResumesFromEachStatus() {
        for status in [Recording.Status.recorded, .transcribing, .transcribed, .analyzing] {
            let recording = makeRecording(status)
            #expect(RecordingPipeline.next(in: [recording])?.id == recording.id, "\(status) should requeue")
        }
        for status in [Recording.Status.ready, .failed] {
            #expect(RecordingPipeline.next(in: [makeRecording(status)]) == nil, "\(status) should not requeue")
        }
    }

    @Test("The queue serves the oldest pending recording first")
    func queueIsOldestFirst() {
        let now = Date()
        let newest = makeRecording(.recorded, createdAt: now)
        let oldest = makeRecording(.transcribed, createdAt: now.addingTimeInterval(-600))
        let done = makeRecording(.ready, createdAt: now.addingTimeInterval(-1_200))

        #expect(RecordingPipeline.next(in: [newest, done, oldest])?.id == oldest.id)
    }

    @Test("An empty library has nothing to do")
    func emptyQueue() {
        #expect(RecordingPipeline.next(in: []) == nil)
    }

    @Test("Retry sends a failure back to the step it can still complete")
    func retryChoosesTheRightStep() throws {
        let container = try RecallModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let pipeline = RecordingPipeline(context: context)

        let untranscribed = makeRecording(.failed)
        untranscribed.failureReason = "modelo ausente"
        context.insert(untranscribed)
        pipeline.retry(untranscribed)
        #expect(untranscribed.status == .recorded)
        #expect(untranscribed.failureReason == nil)

        let transcribed = makeRecording(.failed)
        transcribed.transcriptText = "Já temos o texto."
        transcribed.failureReason = "análise falhou"
        context.insert(transcribed)
        pipeline.retry(transcribed)
        #expect(transcribed.status == .transcribed)
        #expect(transcribed.failureReason == nil)
    }

    @Test("Applying a transcription replaces the segments and recounts the words")
    func applyReplacesSegments() throws {
        let container = try RecallModelContainer.make(inMemory: true)
        let context = ModelContext(container)
        let pipeline = RecordingPipeline(context: context)

        let recording = makeRecording(.transcribing)
        recording.segments = [TranscriptSegment(start: 0, end: 1, text: "texto antigo")]
        context.insert(recording)
        try context.save()

        pipeline.apply(
            TranscriptionOutput(
                text: "Primeiro trecho. Segundo trecho.",
                segments: [
                    TranscribedSegment(start: 0, end: 2.5, text: "Primeiro trecho."),
                    TranscribedSegment(start: 2.5, end: 5, text: "Segundo trecho.")
                ]
            ),
            to: recording
        )
        try context.save()

        #expect(recording.transcriptText == "Primeiro trecho. Segundo trecho.")
        #expect(recording.wordCount == 4)
        #expect(recording.segments.count == 2)

        let ordered = recording.segments.sorted { $0.start < $1.start }
        #expect(ordered.map(\.text) == ["Primeiro trecho.", "Segundo trecho."])
        #expect(ordered[0].start == 0)
        #expect(ordered[1].end == 5)
        #expect(try context.fetch(FetchDescriptor<TranscriptSegment>()).count == 2)
    }
}
