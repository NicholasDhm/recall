import Foundation
import Testing

@testable import Recall

@Suite("Transcript text")
struct TranscriptTextTests {
    @Test("Word count ignores punctuation-only tokens and extra whitespace")
    func wordCount() {
        #expect(TranscriptText.wordCount("") == 0)
        #expect(TranscriptText.wordCount("   \n  ") == 0)
        #expect(TranscriptText.wordCount("Olá mundo") == 2)
        #expect(TranscriptText.wordCount("Olá,   mundo!") == 2)
        #expect(TranscriptText.wordCount("um — dois ... três") == 3)
        #expect(TranscriptText.wordCount("são 25 reais") == 3)
    }

    @Test("Joining segments produces one space between them and drops empties")
    func join() {
        let segments = [
            TranscribedSegment(start: 0, end: 1, text: "Bom dia."),
            TranscribedSegment(start: 1, end: 2, text: ""),
            TranscribedSegment(start: 2, end: 3, text: "Vamos começar.")
        ]
        #expect(TranscriptText.join(segments) == "Bom dia. Vamos começar.")
        #expect(TranscriptText.join([]).isEmpty)
    }

    @Test("Output derives its word count from the joined text")
    func outputWordCount() {
        let output = TranscriptionOutput(
            text: "Bom dia. Vamos começar.",
            segments: [
                TranscribedSegment(start: 0, end: 1, text: "Bom dia."),
                TranscribedSegment(start: 1, end: 3, text: "Vamos começar.")
            ]
        )
        #expect(output.wordCount == 4)
    }
}
