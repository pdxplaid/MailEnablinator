import SwiftUI

@main
struct MailEnablinatorApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra("MailEnablinator", systemImage: appState.menuBarIcon) {
            MenuBarRootView()
                .environment(appState)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsRootView()
                .environment(appState)
        }

        Window("Activity Log", id: "activity-log") {
            ActivityLogWindow()
                .environment(appState)
        }
        .defaultSize(width: 640, height: 400)
    }
}
