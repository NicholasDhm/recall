import Foundation
import SwiftData

enum RecordingActions {
    /// Deleting a recording deletes its audio file; the cascade rule handles the segments.
    static func delete(_ recording: Recording, in context: ModelContext, store: AudioStore = .shared) {
        store.delete(fileName: recording.audioFileName)
        context.delete(recording)
        try? context.save()
    }

    static func deleteAll(in context: ModelContext, store: AudioStore = .shared) {
        let recordings = (try? context.fetch(FetchDescriptor<Recording>())) ?? []
        for recording in recordings {
            store.delete(fileName: recording.audioFileName)
            context.delete(recording)
        }
        try? context.save()
    }
}

extension Recording {
    static func defaultTitle(for date: Date) -> String {
        String(
            localized: "Gravação de \(date.formatted(.dateTime.day().month(.abbreviated).hour().minute()))"
        )
    }

    func matches(query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }
        if title.lowercased().contains(needle) { return true }
        if transcriptText.lowercased().contains(needle) { return true }
        if let summary, summary.lowercased().contains(needle) { return true }
        return tags.contains { $0.lowercased().contains(needle) }
    }
}

extension Recording {
    /// Shown in the Library row only while the pipeline still owes something.
    var statusNotice: String? {
        switch status {
        case .ready: nil
        case .failed: failureReason ?? status.label
        default: status.label
        }
    }
}
