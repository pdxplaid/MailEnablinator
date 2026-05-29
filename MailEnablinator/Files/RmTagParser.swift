import Foundation

enum RmTagParser {
    // True if the tag string is a valid, parseable Rm* tag.
    nonisolated static func isRmTag(_ raw: String) -> Bool {
        parse(raw) != nil
    }

    // Parses an Rm* tag string (with or without the optional space after "Rm").
    // Strips any Finder color-index suffix (\nN) before matching.
    // Returns nil for anything that isn't a valid Rm tag.
    nonisolated static func parse(_ raw: String) -> RmRule? {
        guard let args = rmArgs(from: raw) else { return nil }
        return parseArgs(args)
    }

    // MARK: - Private

    // Returns the argument portion after "Rm[optional space]", lowercased, or nil.
    private nonisolated static func rmArgs(from raw: String) -> String? {
        // Strip Finder color-index suffix "\nN"
        let stripped = raw.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? raw
        let lower = stripped.lowercased()
        guard lower.hasPrefix("rm") else { return nil }
        var args = String(lower.dropFirst(2))
        if args.hasPrefix(" ") { args = String(args.dropFirst()) }
        return args
    }

    private nonisolated static func parseArgs(_ args: String) -> RmRule? {
        // Manual: bare "m", "man", "manual"
        if args == "m" || args == "man" || args == "manual" {
            return .manual
        }

        // Relative with hour: \d+[hdwm]
        if let match = try? /^(\d+)([hdwm])$/.wholeMatch(in: args) {
            guard let n = Int(match.output.1), n > 0 else { return nil }
            switch match.output.2 {
            case "h": return .relative(amount: n, unit: .hour)
            case "d": return .relative(amount: n, unit: .day)
            case "w": return .relative(amount: n, unit: .week)
            case "m": return .relative(amount: n, unit: .month)
            default:  return nil
            }
        }

        // Date with explicit hour: \d+-\d+\+\d+
        if let match = try? /^(\d+)-(\d+)\+(\d+)$/.wholeMatch(in: args) {
            guard
                let month = Int(match.output.1), (1...12).contains(month),
                let day   = Int(match.output.2), (1...31).contains(day),
                let hour  = Int(match.output.3), (0...23).contains(hour)
            else { return nil }
            return .dateAtHour(month: month, day: day, hour: hour)
        }

        // Date (end of day): \d+-\d+
        if let match = try? /^(\d+)-(\d+)$/.wholeMatch(in: args) {
            guard
                let month = Int(match.output.1), (1...12).contains(month),
                let day   = Int(match.output.2), (1...31).contains(day)
            else { return nil }
            return .dateAtEndOfDay(month: month, day: day)
        }

        // Month name (≥3 chars)
        if args.count >= 3, args.allSatisfy(\.isLetter), let month = monthNumber(from: args) {
            return .lastDayOfMonth(month)
        }

        return nil
    }

    private nonisolated static func monthNumber(from str: String) -> Int? {
        let prefixes = ["jan", "feb", "mar", "apr", "may", "jun",
                        "jul", "aug", "sep", "oct", "nov", "dec"]
        for (i, prefix) in prefixes.enumerated() where str.hasPrefix(prefix) {
            return i + 1
        }
        return nil
    }
}
