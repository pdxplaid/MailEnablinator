import Foundation
import Observation

@MainActor
@Observable
final class ActivityLogStore {
    private let maxEntries = 500

    private(set) var entries: [ActivityLogEntry] = []

    func add(_ message: String, level: ActivityLogEntry.Level = .info) {
        entries.append(ActivityLogEntry(date: .now, level: level, message: message))
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    func clear() {
        entries.removeAll()
    }
}
