import Foundation
import Testing

@testable import Recall

@Suite("Insights aggregations")
struct InsightsTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        calendar.firstWeekday = 1
        return calendar
    }

    /// Fixed reference point so nothing in this suite depends on the wall clock.
    private var now: Date {
        DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: 2026, month: 3, day: 18, hour: 15
        ).date!
    }

    private func day(_ offset: Int, hour: Int = 10) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
            .addingTimeInterval(TimeInterval(hour * 3600))
    }

    private func stats(
        daysAgo: Int,
        minutes: Double,
        words: Int = 0,
        tags: [String] = [],
        transcript: String = "",
        hour: Int = 10
    ) -> RecordingStats {
        RecordingStats(
            createdAt: day(-daysAgo, hour: hour),
            duration: minutes * 60,
            wordCount: words,
            tags: tags,
            transcriptText: transcript
        )
    }

    // MARK: - Period

    @Test("The period bounds the window that gets aggregated")
    func periodFilters() {
        let recordings = [
            stats(daysAgo: 0, minutes: 10),
            stats(daysAgo: 5, minutes: 10),
            stats(daysAgo: 20, minutes: 10),
            stats(daysAgo: 100, minutes: 10)
        ]

        #expect(metrics(recordings, .week).totalRecordings == 2)
        #expect(metrics(recordings, .month).totalRecordings == 3)
        #expect(metrics(recordings, .all).totalRecordings == 4)
    }

    @Test("An empty period reports itself as empty rather than crashing")
    func emptyPeriod() {
        let result = metrics([stats(daysAgo: 90, minutes: 10)], .week)
        #expect(result.isEmpty)
        #expect(result.minutesPerDay.isEmpty)
        #expect(result.topWords.isEmpty)
    }

    // MARK: - Per day

    @Test("Minutes add up per day and empty days keep their slot")
    func minutesPerDay() {
        let result = metrics(
            [
                stats(daysAgo: 0, minutes: 5),
                stats(daysAgo: 0, minutes: 7),
                stats(daysAgo: 2, minutes: 3)
            ],
            .week
        )

        #expect(result.minutesPerDay.count == 7)
        #expect(result.minutesPerDay.map(\.day) == result.minutesPerDay.map(\.day).sorted())

        let byDay = Dictionary(uniqueKeysWithValues: result.minutesPerDay.map { ($0.day, $0.value) })
        #expect(byDay[calendar.startOfDay(for: day(0))] == 12)
        #expect(byDay[calendar.startOfDay(for: day(-2))] == 3)
        #expect(byDay[calendar.startOfDay(for: day(-1))] == 0)
    }

    @Test("Recordings landing on the same day are one bar, not two")
    func sameDayCollapses() {
        let result = metrics(
            [stats(daysAgo: 1, minutes: 4, hour: 8), stats(daysAgo: 1, minutes: 6, hour: 22)],
            .week
        )
        let nonZero = result.minutesPerDay.filter { $0.value > 0 }
        #expect(nonZero.count == 1)
        #expect(nonZero.first?.value == 10)
    }

    // MARK: - Per week

    @Test("Recordings group into calendar weeks in chronological order")
    func recordingsPerWeek() {
        let result = metrics(
            [
                stats(daysAgo: 0, minutes: 1),
                stats(daysAgo: 1, minutes: 1),
                stats(daysAgo: 10, minutes: 1),
                stats(daysAgo: 12, minutes: 1),
                stats(daysAgo: 13, minutes: 1)
            ],
            .month
        )

        #expect(result.recordingsPerWeek.map(\.value).reduce(0, +) == 5)
        #expect(result.recordingsPerWeek.map(\.day) == result.recordingsPerWeek.map(\.day).sorted())
        for point in result.recordingsPerWeek {
            #expect(calendar.dateInterval(of: .weekOfYear, for: point.day)?.start == point.day)
        }
    }

    // MARK: - Words per minute

    @Test("Words per minute is words over minutes, per recording")
    func wordsPerMinutePoints() {
        let result = metrics(
            [
                stats(daysAgo: 1, minutes: 2, words: 300),
                stats(daysAgo: 0, minutes: 4, words: 400)
            ],
            .week
        )

        #expect(result.wordsPerMinute.map(\.value) == [150, 100])
    }

    @Test("The period average weights by time instead of averaging the ratios")
    func averageWordsPerMinuteIsWeighted() {
        let result = metrics(
            [
                stats(daysAgo: 1, minutes: 1, words: 200),
                stats(daysAgo: 0, minutes: 9, words: 700)
            ],
            .week
        )
        // 900 words over 10 minutes, not the mean of 200 and ~78.
        #expect(result.averageWordsPerMinute == 90)
    }

    @Test("Recordings without a transcript do not distort words per minute")
    func skipsUntranscribed() {
        let result = metrics(
            [stats(daysAgo: 0, minutes: 5, words: 0), stats(daysAgo: 1, minutes: 2, words: 200)],
            .week
        )
        #expect(result.wordsPerMinute.count == 1)
        #expect(result.averageWordsPerMinute == 100)
    }

    // MARK: - Totals

    @Test("Totals, average duration and the most active weekday")
    func totals() {
        // 2026-03-18 is a Wednesday; two recordings land on Monday.
        let result = metrics(
            [
                stats(daysAgo: 0, minutes: 10),
                stats(daysAgo: 2, minutes: 20),
                stats(daysAgo: 9, minutes: 30)
            ],
            .month
        )

        #expect(result.totalRecordings == 3)
        #expect(result.totalDuration == 60 * 60)
        #expect(result.averageDuration == 20 * 60)
        #expect(result.mostActiveWeekday == calendar.component(.weekday, from: day(-2)))
    }

    // MARK: - Tags

    @Test("Top tags count across recordings, most used first")
    func topTags() {
        let result = metrics(
            [
                stats(daysAgo: 0, minutes: 1, tags: ["reunião", "produto"]),
                stats(daysAgo: 1, minutes: 1, tags: ["reunião", "vendas"]),
                stats(daysAgo: 2, minutes: 1, tags: ["reunião"])
            ],
            .week
        )

        #expect(result.topTags.first == CountedString(name: "reunião", count: 3))
        #expect(result.topTags.count == 3)
        // Ties are alphabetical so the chart order never wobbles.
        #expect(result.topTags.dropFirst().map(\.name) == ["produto", "vendas"])
    }

    @Test("Top tags stop at ten")
    func topTagsLimit() {
        let tags = (1...15).map { "tag\($0)" }
        let result = metrics([stats(daysAgo: 0, minutes: 1, tags: tags)], .week)
        #expect(result.topTags.count == InsightsMetrics.topTagLimit)
    }

    // MARK: - Words

    @Test("Top words drop stopwords in both languages and count the rest")
    func topWords() {
        let stopwords = Stopwords.load(bundle: .main)
        #expect(stopwords.contains("de"))
        #expect(stopwords.contains("the"))

        let result = InsightsMetrics.make(
            from: [
                stats(
                    daysAgo: 0,
                    minutes: 1,
                    transcript: "O relatório de vendas e o relatório de custos. The report is here."
                )
            ],
            period: .week,
            now: now,
            calendar: calendar,
            stopwords: stopwords
        )

        let counts = Dictionary(uniqueKeysWithValues: result.topWords.map { ($0.name, $0.count) })
        #expect(counts["relatório"] == 2)
        #expect(counts["vendas"] == 1)
        #expect(counts["report"] == 1)
        #expect(counts["de"] == nil)
        #expect(counts["the"] == nil)
        #expect(counts["is"] == nil)
        #expect(result.topWords.first?.name == "relatório")
    }

    @Test("Tokenising lower-cases, strips punctuation and drops single characters")
    func tokenising() {
        #expect(InsightsMetrics.words(in: "Olá, mundo! Tudo bem?") == ["olá", "mundo", "tudo", "bem"])
        #expect(InsightsMetrics.words(in: "a b cd 12 3") == ["cd", "12"])
        #expect(InsightsMetrics.words(in: "").isEmpty)
    }

    @Test("Top words stop at twenty")
    func topWordsLimit() {
        let transcript = (1...30).map { "palavra\($0)" }.joined(separator: " ")
        let result = InsightsMetrics.make(
            from: [stats(daysAgo: 0, minutes: 1, transcript: transcript)],
            period: .week,
            now: now,
            calendar: calendar,
            stopwords: []
        )
        #expect(result.topWords.count == InsightsMetrics.topWordLimit)
    }

    @Test("The bundled stopword list actually loads")
    func stopwordsResourceLoads() {
        let stopwords = Stopwords.load(bundle: .main)
        #expect(stopwords.count > 100)
        #expect(!stopwords.contains(""))
        #expect(!stopwords.contains { $0.hasPrefix("#") })
    }

    private func metrics(_ recordings: [RecordingStats], _ period: InsightsPeriod) -> InsightsMetrics {
        InsightsMetrics.make(
            from: recordings,
            period: period,
            now: now,
            calendar: calendar,
            stopwords: []
        )
    }
}
