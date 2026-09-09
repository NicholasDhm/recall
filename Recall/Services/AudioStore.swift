import Foundation

/// Locates, deletes and measures the recorded audio files.
///
/// Files live in `Application Support/Recordings/` — not `Documents`, which is
/// user-visible in Files and gets backed up as user data.
struct AudioStore: Sendable {
    let directory: URL

    static let shared = AudioStore(
        directory: URL.applicationSupportDirectory.appending(path: "Recordings", directoryHint: .isDirectory)
    )

    func createDirectoryIfNeeded() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func url(for fileName: String) -> URL {
        directory.appending(path: fileName, directoryHint: .notDirectory)
    }

    func makeFileName(id: UUID) -> String {
        "\(id.uuidString).\(AudioFormat.fileExtension)"
    }

    func delete(fileName: String) {
        try? FileManager.default.removeItem(at: url(for: fileName))
    }

    func exists(fileName: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: fileName).path(percentEncoded: false))
    }

    func byteCount(of fileName: String) -> Int64 {
        let values = try? url(for: fileName).resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    func totalByteCount() -> Int64 {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)) else {
            return 0
        }
        return names.reduce(0) { $0 + byteCount(of: $1) }
    }

    /// Copies an imported file into the store, converting nothing: the transcriber
    /// reads whatever container the user picked.
    func importFile(from source: URL, id: UUID) throws -> String {
        try createDirectoryIfNeeded()
        let fileExtension = source.pathExtension.isEmpty ? AudioFormat.fileExtension : source.pathExtension
        let fileName = "\(id.uuidString).\(fileExtension)"
        let destination = url(for: fileName)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)
        return fileName
    }
}
