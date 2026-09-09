import Foundation
import SwiftData

@Model
final class Recording {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var title: String = ""
    var duration: TimeInterval = 0
    /// Relative to `Application Support/Recordings/`. Absolute URLs are never persisted,
    /// because the container path changes between installs.
    var audioFileName: String = ""
    var localeIdentifier: String = "pt-BR"
    var sourceRawValue: String = Source.microphone.rawValue
    var statusRawValue: String = Status.recorded.rawValue
    var failureReason: String?
    var transcriptText: String = ""
    @Relationship(deleteRule: .cascade, inverse: \TranscriptSegment.recording)
    var segments: [TranscriptSegment] = []
    var summary: String?
    var tags: [String] = []
    var actionItems: [String] = []
    var wordCount: Int = 0

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        title: String,
        duration: TimeInterval,
        audioFileName: String,
        localeIdentifier: String,
        source: Source,
        status: Status = .recorded
    ) {
        self.id = id
        self.createdAt = createdAt
        self.title = title
        self.duration = duration
        self.audioFileName = audioFileName
        self.localeIdentifier = localeIdentifier
        self.sourceRawValue = source.rawValue
        self.statusRawValue = status.rawValue
    }

    var source: Source {
        get { Source(rawValue: sourceRawValue) ?? .microphone }
        set { sourceRawValue = newValue.rawValue }
    }

    var status: Status {
        get { Status(rawValue: statusRawValue) ?? .recorded }
        set { statusRawValue = newValue.rawValue }
    }

    enum Source: String, Codable, CaseIterable, Sendable {
        case microphone
        case imported
    }

    enum Status: String, Codable, CaseIterable, Sendable {
        case recorded
        case transcribing
        case transcribed
        case analyzing
        case ready
        case failed
    }
}

@Model
final class TranscriptSegment {
    var start: TimeInterval = 0
    var end: TimeInterval = 0
    var text: String = ""
    var recording: Recording?

    init(start: TimeInterval, end: TimeInterval, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}
