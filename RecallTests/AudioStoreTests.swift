import Foundation
import Testing

@testable import Recall

@Suite("Audio store")
struct AudioStoreTests {
    private func makeStore() throws -> AudioStore {
        let store = AudioStore(
            directory: FileManager.default.temporaryDirectory
                .appending(path: "AudioStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        )
        try store.createDirectoryIfNeeded()
        return store
    }

    private func write(_ name: String, bytes: Int, to store: AudioStore) throws {
        try Data(repeating: 0x41, count: bytes).write(to: store.url(for: name))
    }

    @Test("File names are derived from the recording id and stay relative")
    func fileNaming() throws {
        let store = try makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }

        let id = UUID()
        let name = store.makeFileName(id: id)
        #expect(name == "\(id.uuidString).m4a")
        #expect(!name.contains("/"))
        #expect(store.url(for: name).deletingLastPathComponent() == store.directory)
    }

    @Test("Deleting removes the file from disk")
    func deleteRemovesFile() throws {
        let store = try makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }

        let name = store.makeFileName(id: UUID())
        try write(name, bytes: 128, to: store)
        #expect(store.exists(fileName: name))

        store.delete(fileName: name)
        #expect(!store.exists(fileName: name))
    }

    @Test("Byte counts add up across the directory")
    func byteCounts() throws {
        let store = try makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }

        try write("a.m4a", bytes: 100, to: store)
        try write("b.m4a", bytes: 250, to: store)

        #expect(store.byteCount(of: "a.m4a") == 100)
        #expect(store.totalByteCount() == 350)
        #expect(store.byteCount(of: "missing.m4a") == 0)
    }

    @Test("Importing copies the source in and keeps its extension")
    func importKeepsExtension() throws {
        let store = try makeStore()
        defer { try? FileManager.default.removeItem(at: store.directory) }

        let source = FileManager.default.temporaryDirectory.appending(path: "source-\(UUID().uuidString).wav")
        try Data(repeating: 0x42, count: 64).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        let id = UUID()
        let name = try store.importFile(from: source, id: id)
        #expect(name == "\(id.uuidString).wav")
        #expect(store.exists(fileName: name))
        #expect(store.byteCount(of: name) == 64)
        #expect(FileManager.default.fileExists(atPath: source.path(percentEncoded: false)))
    }
}
