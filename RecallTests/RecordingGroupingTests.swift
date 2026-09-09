import Foundation
import Testing

@testable import Recall

@Suite("Library grouping")
struct RecordingGroupingTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        calendar.firstWeekday = 1
        return calendar
    }

    /// A Wednesday, so "this week" still has earlier days in it.
    private var now: Date {
        DateComponents(
            calendar: calendar, timeZone: calendar.timeZone,
            year: 2026, month: 3, day: 18, hour: 15
        ).date!
    }

    private func date(daysAgo: Int, hour: Int = 10) -> Date {
        calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: now))!
            .addingTimeInterval(TimeInterval(hour * 3600))
    }

    private func group(daysAgo: Int) -> RecordingGroup {
        RecordingGroup.of(date(daysAgo: daysAgo), now: now, calendar: calendar)
    }

    @Test("Each date falls in the bucket a reader would expect")
    func buckets() {
        #expect(group(daysAgo: 0) == .today)
        #expect(group(daysAgo: 1) == .yesterday)
        #expect(group(daysAgo: 2) == .thisWeek)   // Monday of the same week
        #expect(group(daysAgo: 9) == .thisMonth)  // earlier in March
        #expect(group(daysAgo: 60) == .earlier)
    }

    @Test("Buckets come back newest first and empty ones are dropped")
    func bucketOrder() {
        let dates = [date(daysAgo: 60), date(daysAgo: 0), date(daysAgo: 9)]
        let sections = RecordingGroup.bucket(dates, date: { $0 }, now: now, calendar: calendar)

        #expect(sections.map(\.group) == [.today, .thisMonth, .earlier])
        #expect(!sections.contains { $0.group == .yesterday })
        #expect(sections.allSatisfy { !$0.items.isEmpty })
    }

    @Test("Every recording lands in exactly one bucket")
    func bucketsPartition() {
        let dates = (0..<40).map { date(daysAgo: $0) }
        let sections = RecordingGroup.bucket(dates, date: { $0 }, now: now, calendar: calendar)
        #expect(sections.reduce(0) { $0 + $1.items.count } == dates.count)
    }

    @Test("Nothing in, nothing out")
    func empty() {
        #expect(RecordingGroup.bucket([Date](), date: { $0 }, now: now, calendar: calendar).isEmpty)
    }
}
