import Foundation

/// Date buckets for the Library timeline.
enum RecordingGroup: Int, CaseIterable, Sendable {
    case today
    case yesterday
    case thisWeek
    case thisMonth
    case earlier

    var title: String {
        switch self {
        case .today: String(localized: "Hoje")
        case .yesterday: String(localized: "Ontem")
        case .thisWeek: String(localized: "Esta semana")
        case .thisMonth: String(localized: "Este mês")
        case .earlier: String(localized: "Mais antigas")
        }
    }

    static func of(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> RecordingGroup {
        // Compared against `now`, not the system clock: isDateInToday ignores it.
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return .yesterday
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) { return .thisWeek }
        if calendar.isDate(date, equalTo: now, toGranularity: .month) { return .thisMonth }
        return .earlier
    }

    /// Buckets in calendar order, newest first, skipping empty ones.
    static func bucket<T>(
        _ items: [T],
        date: (T) -> Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [(group: RecordingGroup, items: [T])] {
        var buckets: [RecordingGroup: [T]] = [:]
        for item in items {
            buckets[of(date(item), now: now, calendar: calendar), default: []].append(item)
        }
        return allCases.compactMap { group in
            guard let items = buckets[group], !items.isEmpty else { return nil }
            return (group, items)
        }
    }
}
