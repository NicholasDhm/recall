import Foundation

/// The fields the Insights tab needs, lifted out of SwiftData so every aggregation
/// below is a pure function over values.
struct RecordingStats: Sendable, Equatable {
    var createdAt: Date
    var duration: TimeInterval
    var wordCount: Int
    var tags: [String]
    var transcriptText: String
}

extension Recording {
    var stats: RecordingStats {
        RecordingStats(
            createdAt: createdAt,
            duration: duration,
            wordCount: wordCount,
            tags: tags,
            transcriptText: transcriptText
        )
    }
}

enum InsightsPeriod: String, CaseIterable, Identifiable, Sendable {
    case week
    case month
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: String(localized: "7 dias")
        case .month: String(localized: "30 dias")
        case .all: String(localized: "Tudo")
        }
    }

    var days: Int? {
        switch self {
        case .week: 7
        case .month: 30
        case .all: nil
        }
    }

    /// Inclusive range of days the period covers, or nil for everything.
    func startDay(now: Date, calendar: Calendar) -> Date? {
        guard let days else { return nil }
        let today = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: -(days - 1), to: today)
    }
}

struct DayValue: Identifiable, Sendable, Equatable {
    var day: Date
    var value: Double
    var id: Date { day }
}

struct CountedString: Identifiable, Sendable, Equatable {
    var name: String
    var count: Int
    var id: String { name }
}

struct InsightsMetrics: Sendable, Equatable {
    var totalRecordings = 0
    var totalDuration: TimeInterval = 0
    var averageDuration: TimeInterval = 0
    var mostActiveWeekday: Int?
    var minutesPerDay: [DayValue] = []
    var recordingsPerWeek: [DayValue] = []
    var wordsPerMinute: [DayValue] = []
    var averageWordsPerMinute: Double = 0
    var topTags: [CountedString] = []
    var topWords: [CountedString] = []

    var isEmpty: Bool { totalRecordings == 0 }

    static let topTagLimit = 10
    static let topWordLimit = 20

    static func make(
        from recordings: [RecordingStats],
        period: InsightsPeriod,
        now: Date = .now,
        calendar: Calendar = .current,
        stopwords: Set<String> = Stopwords.all
    ) -> InsightsMetrics {
        let start = period.startDay(now: now, calendar: calendar)
        let scoped = recordings
            .filter { start == nil || $0.createdAt >= start! }
            .sorted { $0.createdAt < $1.createdAt }

        var metrics = InsightsMetrics()
        guard !scoped.isEmpty else { return metrics }

        metrics.totalRecordings = scoped.count
        metrics.totalDuration = scoped.reduce(0) { $0 + $1.duration }
        metrics.averageDuration = metrics.totalDuration / Double(scoped.count)
        metrics.mostActiveWeekday = mostActiveWeekday(in: scoped, calendar: calendar)
        metrics.minutesPerDay = minutesPerDay(
            in: scoped,
            from: start,
            now: now,
            calendar: calendar
        )
        metrics.recordingsPerWeek = recordingsPerWeek(in: scoped, calendar: calendar)
        metrics.wordsPerMinute = scoped.compactMap { recording in
            guard recording.duration > 0, recording.wordCount > 0 else { return nil }
            return DayValue(
                day: recording.createdAt,
                value: Double(recording.wordCount) / (recording.duration / 60)
            )
        }

        // Weighted by time, not the mean of per-recording ratios.
        let spokenMinutes = scoped
            .filter { $0.wordCount > 0 }
            .reduce(0) { $0 + $1.duration } / 60
        let spokenWords = scoped.reduce(0) { $0 + $1.wordCount }
        metrics.averageWordsPerMinute = spokenMinutes > 0 ? Double(spokenWords) / spokenMinutes : 0

        metrics.topTags = topTags(in: scoped)
        metrics.topWords = topWords(in: scoped, stopwords: stopwords)
        return metrics
    }

    static func minutesPerDay(
        in recordings: [RecordingStats],
        from start: Date?,
        now: Date,
        calendar: Calendar
    ) -> [DayValue] {
        var totals: [Date: Double] = [:]
        for recording in recordings {
            let day = calendar.startOfDay(for: recording.createdAt)
            totals[day, default: 0] += recording.duration / 60
        }

        // Days with no recording still need a slot so the bars keep their spacing.
        let today = calendar.startOfDay(for: now)
        let firstDay = start ?? totals.keys.min() ?? today
        guard firstDay <= today else { return [] }

        var days: [DayValue] = []
        var cursor = firstDay
        while cursor <= today {
            days.append(DayValue(day: cursor, value: totals[cursor] ?? 0))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    static func recordingsPerWeek(
        in recordings: [RecordingStats],
        calendar: Calendar
    ) -> [DayValue] {
        var totals: [Date: Double] = [:]
        for recording in recordings {
            guard let week = calendar.dateInterval(of: .weekOfYear, for: recording.createdAt)?.start else {
                continue
            }
            totals[week, default: 0] += 1
        }
        return totals
            .map { DayValue(day: $0.key, value: $0.value) }
            .sorted { $0.day < $1.day }
    }

    static func mostActiveWeekday(in recordings: [RecordingStats], calendar: Calendar) -> Int? {
        var counts: [Int: Int] = [:]
        for recording in recordings {
            counts[calendar.component(.weekday, from: recording.createdAt), default: 0] += 1
        }
        // Ties resolve to the earlier weekday so the answer is stable.
        return counts.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key
    }

    static func topTags(in recordings: [RecordingStats], limit: Int = topTagLimit) -> [CountedString] {
        var counts: [String: Int] = [:]
        for tag in recordings.flatMap(\.tags) {
            let cleaned = tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !cleaned.isEmpty else { continue }
            counts[cleaned, default: 0] += 1
        }
        return rank(counts, limit: limit)
    }

    static func topWords(
        in recordings: [RecordingStats],
        stopwords: Set<String>,
        limit: Int = topWordLimit
    ) -> [CountedString] {
        var counts: [String: Int] = [:]
        for recording in recordings {
            for word in words(in: recording.transcriptText) where !stopwords.contains(word) {
                counts[word, default: 0] += 1
            }
        }
        return rank(counts, limit: limit)
    }

    /// Lower-cased tokens of two or more letters or digits, punctuation stripped.
    static func words(in text: String) -> [String] {
        text
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 1 }
    }

    /// Highest count first, alphabetical within a tie so the order never wobbles.
    private static func rank(_ counts: [String: Int], limit: Int) -> [CountedString] {
        counts
            .map { CountedString(name: $0.key, count: $0.value) }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
            .prefix(limit)
            .map { $0 }
    }
}

enum Stopwords {
    static let all: Set<String> = load()

    static func load(bundle: Bundle = .main) -> Set<String> {
        guard let url = bundle.url(forResource: "stopwords", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return Set(
            text
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        )
    }
}
