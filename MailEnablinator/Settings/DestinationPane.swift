import SwiftUI
import UniformTypeIdentifiers

struct DestinationPane: View {
    @Environment(AppState.self) private var appState
    @State private var showFolderPicker = false

    private var store: DestinationStore { appState.destinationStore }

    var body: some View {
        Form {
            Section("Save Location") {
                HStack {
                    if let name = store.displayName {
                        Label(name, systemImage: "folder.fill")
                    } else {
                        Text("No folder selected")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Choose…", systemImage: "folder") {
                        showFolderPicker = true
                    }
                }
            }

            Section {
                Picker(
                    "Default Tag",
                    selection: Binding(get: { store.defaultRmTag }, set: { store.defaultRmTag = $0 })
                ) {
                    ForEach(DefaultRmTag.allCases, id: \.self) { tag in
                        Text(tag.rawValue).tag(tag)
                    }
                }
                .pickerStyle(.segmented)
                Text("Applied to images whose email body has no Rm-style tag.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } header: {
                Text("Default Finder Tag")
            }
        }
        .formStyle(.grouped)
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            let didScope = url.startAccessingSecurityScopedResource()
            store.saveDestination(url: url)
            if didScope { url.stopAccessingSecurityScopedResource() }
        }
    }
}
