import Foundation

struct ActivityLogEntry: Identifiable, Sendable {
    let id = UUID()
    let date: Date
    let level: Level
    let message: String

    enum Level: Sendable {
        case info, success, warning, error
    }
}
