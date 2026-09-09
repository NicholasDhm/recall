import Foundation
import SwiftData
import Testing

@testable import Recall

@MainActor
@Suite("Recordings")
struct RecordingTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try RecallModelContainer.make(inMemory: true))
    }

    private func makeRecording(
        title: String = "Reunião de equipe",
        transcript: String = "Falamos sobre o lançamento e o orçamento.",
        tags: [String] = ["reunião", "produto"],
        summary: String? = "Alinhamento do lançamento.",
        fileName: String = "sample.m4a"
    ) -> Recording {
        let recording = Recording(
            title: title,
            duration: 90,
            audioFileName: fileName,
            localeIdentifier: "pt-BR",
            source: .microphone
        )
        recording.transcriptText = transcript
        recording.tags = tags
        recording.summary = summary
        return recording
    }

    @Test("Status and source survive the round-trip through their raw values")
    func enumRoundTrip() throws {
        let context = try makeContext()
        let recording = makeRecording()
        context.insert(recording)

        recording.status = .analyzing
        recording.source = .imported
        try context.save()

        let stored = try #require(try context.fetch(FetchDescriptor<Recording>()).first)
        #expect(stored.status == .analyzing)
        #expect(stored.source == .imported)
    }

    @Test("Search matches title, transcript, summary and tags, case-insensitively")
    func search() {
        let recording = makeRecording()
        #expect(recording.matches(query: ""))
        #expect(recording.matches(query: "reunião"))
        #expect(recording.matches(query: "REUNIÃO"))
        #expect(recording.matches(query: "orçamento"))
        #expect(recording.matches(query: "lançamento"))
        #expect(recording.matches(query: "produto"))
        #expect(!recording.matches(query: "bicicleta"))
    }

    @Test("Search ignores surrounding whitespace")
    func searchTrimsQuery() {
        #expect(makeRecording().matches(query: "  equipe  "))
    }

    @Test("Deleting a recording deletes its audio file and the row")
    func deleteRemovesAudioAndRow() throws {
        let store = AudioStore(
            directory: FileManager.default.temporaryDirectory
                .appending(path: "RecordingTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        )
        try store.createDirectoryIfNeeded()
        defer { try? FileManager.default.removeItem(at: store.directory) }

        let name = store.makeFileName(id: UUID())
        try Data(repeating: 0, count: 32).write(to: store.url(for: name))

        let context = try makeContext()
        let recording = makeRecording(fileName: name)
        context.insert(recording)
        try context.save()

        RecordingActions.delete(recording, in: context, store: store)

        #expect(!store.exists(fileName: name))
        #expect(try context.fetch(FetchDescriptor<Recording>()).isEmpty)
    }

    @Test("Deleting a recording cascades to its transcript segments")
    func deleteCascadesToSegments() throws {
        let context = try makeContext()
        let recording = makeRecording()
        recording.segments = [
            TranscriptSegment(start: 0, end: 2, text: "Olá"),
            TranscriptSegment(start: 2, end: 4, text: "tudo bem")
        ]
        context.insert(recording)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<TranscriptSegment>()).count == 2)

        RecordingActions.delete(recording, in: context)
        #expect(try context.fetch(FetchDescriptor<TranscriptSegment>()).isEmpty)
    }

    @Test("Deleting everything empties the store and the disk")
    func deleteAll() throws {
        let store = AudioStore(
            directory: FileManager.default.temporaryDirectory
                .appending(path: "RecordingTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        )
        try store.createDirectoryIfNeeded()
        defer { try? FileManager.default.removeItem(at: store.directory) }

        let context = try makeContext()
        for index in 0..<3 {
            let name = store.makeFileName(id: UUID())
            try Data(repeating: 0, count: 16).write(to: store.url(for: name))
            context.insert(makeRecording(title: "Gravação \(index)", fileName: name))
        }
        try context.save()
        #expect(store.totalByteCount() == 48)

        RecordingActions.deleteAll(in: context, store: store)

        #expect(try context.fetch(FetchDescriptor<Recording>()).isEmpty)
        #expect(store.totalByteCount() == 0)
    }

    @Test("Clock formatting stays readable past an hour")
    func clockFormatting() {
        #expect(DurationFormat.clock(0) == "0:00")
        #expect(DurationFormat.clock(9) == "0:09")
        #expect(DurationFormat.clock(75) == "1:15")
        #expect(DurationFormat.clock(3_661) == "1:01:01")
    }
}
