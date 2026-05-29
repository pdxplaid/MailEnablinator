import Foundation

enum RmRule: Sendable {
    enum TimeUnit: Sendable { case hour, day, week, month }

    case manual
    case relative(amount: Int, unit: TimeUnit)
    case dateAtEndOfDay(month: Int, day: Int)
    case dateAtHour(month: Int, day: Int, hour: Int)
    case lastDayOfMonth(Int)

    // Returns nil for .manual (never archive).
    // All "end of day" cases resolve to startOfDay(target + 1 day) per user spec.
    nonisolated func dueDate(addedAt: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .manual:
            return nil

        case .relative(let n, .hour):
            return calendar.date(byAdding: .hour, value: n, to: ceilingToHour(addedAt, calendar: calendar))

        case .relative(let n, .day):
            // End of the Nth day after the calendar day the file was added.
            // e.g. Rm2D added June 1 → startOfDay(June 1) + 3 days = June 4 00:00 (= end of June 3)
            let start = calendar.startOfDay(for: addedAt)
            return calendar.date(byAdding: .day, value: n + 1, to: start)

        case .relative(let n, .week):
            let start = calendar.startOfDay(for: addedAt)
            return calendar.date(byAdding: .day, value: 7 * n + 1, to: start)

        case .relative(let n, .month):
            let start = calendar.startOfDay(for: addedAt)
            guard let monthLater = calendar.date(byAdding: .month, value: n, to: start) else { return nil }
            return calendar.date(byAdding: .day, value: 1, to: monthLater)

        case .dateAtEndOfDay(let month, let day):
            // End of the given month/day = startOfDay(that day) + 1 day.
            // If that instant is not strictly after addedAt, advance to next year.
            return nextOccurrence(
                month: month, day: day, hour: 0, endOfDay: true,
                after: addedAt, calendar: calendar
            )

        case .dateAtHour(let month, let day, let hour):
            return nextOccurrence(
                month: month, day: day, hour: hour, endOfDay: false,
                after: addedAt, calendar: calendar
            )

        case .lastDayOfMonth(let month):
            let year = calendar.component(.year, from: addedAt)
            for offset in 0...1 {
                guard
                    let firstOfMonth = calendar.date(
                        from: DateComponents(year: year + offset, month: month, day: 1)
                    ),
                    let range = calendar.range(of: .day, in: .month, for: firstOfMonth)
                else { continue }
                let lastDay = range.upperBound - 1
                guard
                    let lastDayStart = calendar.date(
                        from: DateComponents(year: year + offset, month: month, day: lastDay)
                    ),
                    let endOfLastDay = calendar.date(byAdding: .day, value: 1, to: lastDayStart)
                else { continue }
                if endOfLastDay > addedAt { return endOfLastDay }
            }
            return nil
        }
    }

    // MARK: - Private helpers

    private nonisolated func ceilingToHour(_ date: Date, calendar: Calendar) -> Date {
        var comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date)
        let needsRound = (comps.minute ?? 0) > 0
            || (comps.second ?? 0) > 0
            || (comps.nanosecond ?? 0) > 0
        guard needsRound else { return date }
        comps.minute = 0
        comps.second = 0
        comps.nanosecond = 0
        comps.hour = (comps.hour ?? 0) + 1
        return calendar.date(from: comps) ?? date
    }

    private nonisolated func nextOccurrence(
        month: Int, day: Int, hour: Int, endOfDay: Bool,
        after addedAt: Date, calendar: Calendar
    ) -> Date? {
        let year = calendar.component(.year, from: addedAt)
        for offset in 0...1 {
            guard let base = calendar.date(
                from: DateComponents(year: year + offset, month: month, day: day, hour: hour)
            ) else { continue }
            let target = endOfDay
                ? (calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: base)) ?? base)
                : base
            if target > addedAt { return target }
        }
        return nil
    }
}
