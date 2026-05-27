import SwiftUI

struct MenuBarRootView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        statusItem
        Divider()
        Button("Open Settings…") {
            openSettings()
        }
        Button("Show Activity Log…") {
            openWindow(id: "activity-log")
        }
        Divider()
        Button("Check Now") {
            Task { await appState.checkNow() }
        }
        .disabled(!appState.isConnected)
        Divider()
        Button("Quit MailEnablinator") {
            NSApplication.shared.terminate(nil)
        }
    }

    private var statusItem: some View {
        let label: String
        switch appState.connectionState {
        case .disconnected: label = "Not connected"
        case .connecting: label = "Connecting…"
        case .idle: label = "Watching for mail"
        case .processing: label = "Processing…"
        case .error(let msg): label = "Error: \(msg)"
        }
        return Text(label)
            .foregroundStyle(.secondary)
    }
}
