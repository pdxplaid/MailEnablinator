import Foundation

enum CullInterval: String, CaseIterable, Sendable {
    case minute = "Every Minute"
    case hour   = "Every Hour"

    var seconds: Int {
        switch self {
        case .minute: 60
        case .hour:   3_600
        }
    }
}
