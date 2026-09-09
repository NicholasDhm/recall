import AVFoundation
import Foundation
import SwiftData
import Testing

@testable import Recall

/// End-to-end exercise of the capture path against the real audio input. Skipped when
/// the microphone has not been granted, so it never fails on a fresh machine.
@MainActor
@Suite("Recording pipeline", .serialized)
struct RecordingPipelineTests {
    @Test("Recording produces a playable file whose duration matches the elapsed time")
    func recordThenPlayThenDelete() async throws {
        try #require(
            AudioRecorder.permission == .granted,
            "grant with: xcrun simctl privacy booted grant microphone com.nickdhm.recall"
        )

        let store = AudioStore(
            directory: FileManager.default.temporaryDirectory
                .appending(path: "PipelineTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        )
        try store.createDirectoryIfNeeded()
        defer { try? FileManager.default.removeItem(at: store.directory) }

        let recorder = AudioRecorder(store: store)
        let id = UUID()
        try recorder.start(id: id)
        #expect(recorder.isRecording)

        try await Task.sleep(for: .seconds(1.5))

        let finished = try #require(recorder.stop())
        #expect(!recorder.isRecording)
        #expect(finished.fileName == "\(id.uuidString).m4a")
        #expect(store.exists(fileName: finished.fileName))
        #expect(finished.duration > 0.5)
        #expect(store.byteCount(of: finished.fileName) > 0)

        let context = ModelContext(try RecallModelContainer.make(inMemory: true))
        let recording = Recording(
            id: id,
            title: Recording.defaultTitle(for: .now),
            duration: finished.duration,
            audioFileName: finished.fileName,
            localeIdentifier: "pt-BR",
            source: .microphone
        )
        context.insert(recording)
        try context.save()

        let playback = AudioPlayback()
        try playback.load(url: store.url(for: finished.fileName))
        #expect(abs(playback.duration - finished.duration) < 0.35)
        playback.seek(to: 0.5)
        #expect(abs(playback.currentTime - 0.5) < 0.05)
        playback.stop()

        RecordingActions.delete(recording, in: context, store: store)
        #expect(!store.exists(fileName: finished.fileName))
        #expect(try context.fetch(FetchDescriptor<Recording>()).isEmpty)
    }
}
