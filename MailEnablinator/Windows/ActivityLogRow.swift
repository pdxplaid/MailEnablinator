import SwiftUI

struct ActivityLogRow: View {
    let entry: ActivityLogEntry

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(entry.date, format: .dateTime.hour().minute().second())
                .foregroundStyle(.secondary)
                .font(.caption.monospaced())
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .font(.caption)
            Text(entry.message)
                .font(.caption)
                .textSelection(.enabled)
        }
    }

    private var iconName: String {
        switch entry.level {
        case .info: "info.circle"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.circle.fill"
        }
    }

    private var iconColor: Color {
        switch entry.level {
        case .info: .secondary
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }
}
