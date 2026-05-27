import SwiftUI

struct SettingsRootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            Tab("Users", systemImage: "person.2") {
                UsersPane()
                    .environment(appState)
            }
            Tab("Destination", systemImage: "folder") {
                DestinationPane()
                    .environment(appState)
            }
            Tab("Mail Account", systemImage: "envelope") {
                MailAccountPane()
                    .environment(appState)
            }
            Tab("Replies", systemImage: "text.bubble") {
                RepliesPane()
                    .environment(appState)
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}
