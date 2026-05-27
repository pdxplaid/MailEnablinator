import SwiftUI

struct RepliesPane: View {
    @Environment(AppState.self) private var appState

    private var store: RepliesStore { appState.repliesStore }

    var body: some View {
        Form {
            Section {
                TextEditor(
                    text: Binding(get: { store.noImageReply }, set: { store.noImageReply = $0 })
                )
                .frame(minHeight: 80)
            } header: {
                Text("No Image Included")
            } footer: {
                Text("Sent when a known sender's email contains no image attachment.")
                    .foregroundStyle(.secondary)
            }

            Section {
                TextEditor(
                    text: Binding(get: { store.nonImageReply }, set: { store.nonImageReply = $0 })
                )
                .frame(minHeight: 80)
            } header: {
                Text("Non-Image Attachment Only")
            } footer: {
                Text("Sent when a known sender sends only non-image attachments.")
                    .foregroundStyle(.secondary)
            }

            Section {
                TextEditor(
                    text: Binding(get: { store.mixedReply }, set: { store.mixedReply = $0 })
                )
                .frame(minHeight: 80)
            } header: {
                Text("Image Processed, Other Files Ignored")
            } footer: {
                Text("Sent when a known sender's email has both image and non-image attachments.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
