import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// Plain-text export of a recording: title, date, summary, action items and transcript.
struct MarkdownExport: Sendable {
    var title: String
    var text: String

    static func make(
        title: String,
        createdAt: Date,
        duration: TimeInterval,
        summary: String?,
        tags: [String],
        actionItems: [String],
        segments: [TranscribedSegment],
        transcriptText: String
    ) -> MarkdownExport {
        var lines: [String] = ["# \(title)", ""]
        lines.append("\(createdAt.formatted(date: .long, time: .shortened)) · \(DurationFormat.clock(duration))")

        if !tags.isEmpty {
            lines.append("")
            lines.append(tags.map { "#\($0)" }.joined(separator: " "))
        }

        if let summary, !summary.isEmpty {
            lines.append(contentsOf: ["", "## Resumo", "", summary])
        }

        if !actionItems.isEmpty {
            lines.append(contentsOf: ["", "## Itens de ação", ""])
            lines.append(contentsOf: actionItems.map { "- [ ] \($0)" })
        }

        lines.append(contentsOf: ["", "## Transcrição", ""])
        if segments.isEmpty {
            lines.append(transcriptText.isEmpty ? "_Sem transcrição._" : transcriptText)
        } else {
            lines.append(
                contentsOf: segments.map { "**\(DurationFormat.clock($0.start))** \($0.text)" }
            )
        }

        return MarkdownExport(title: title, text: lines.joined(separator: "\n") + "\n")
    }

    /// Sanitised so the share sheet offers a sensible file name.
    var fileName: String {
        let cleaned = title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned.isEmpty ? "Gravação" : cleaned) + ".md"
    }
}

extension Recording {
    var markdownExport: MarkdownExport {
        MarkdownExport.make(
            title: title,
            createdAt: createdAt,
            duration: duration,
            summary: summary,
            tags: tags,
            actionItems: actionItems,
            segments: segments
                .sorted { $0.start < $1.start }
                .map { TranscribedSegment(start: $0.start, end: $0.end, text: $0.text) },
            transcriptText: transcriptText
        )
    }
}

extension MarkdownExport: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { export in
            Data(export.text.utf8)
        }
        .suggestedFileName { $0.fileName }
    }
}
