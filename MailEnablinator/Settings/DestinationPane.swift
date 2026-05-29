import SwiftUI
import UniformTypeIdentifiers

private enum FolderTarget { case destination, archive }

struct DestinationPane: View {
    @Environment(AppState.self) private var appState
    @State private var showingPicker = false
    @State private var pickerTarget: FolderTarget = .destination

    private var store: DestinationStore { appState.destinationStore }

    var body: some View {
        Form {
            Section("Saved Locations") {
                FolderPickerRow(
                    label: "Destination",
                    path: store.destinationPath,
                    onChoose: { pickerTarget = .destination; showingPicker = true }
                )
                FolderPickerRow(
                    label: "Archives",
                    path: store.archivePath,
                    onChoose: { pickerTarget = .archive; showingPicker = true }
                )
                Toggle(
                    "Put archived images into subfolders by date",
                    isOn: Binding(
                        get: { store.archiveUseDateSubfolders },
                        set: { store.archiveUseDateSubfolders = $0 }
                    )
                )
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
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            let didScope = url.startAccessingSecurityScopedResource()
            switch pickerTarget {
            case .destination: store.saveDestination(url: url)
            case .archive:     store.saveArchive(url: url)
            }
            if didScope { url.stopAccessingSecurityScopedResource() }
        }
    }
}

private struct FolderPickerRow: View {
    let label: String
    let path: String?
    let onChoose: () -> Void

    var body: some View {
        HStack {
            Text(label)
                .bold()
                .frame(minWidth: 90, alignment: .leading)
            if let path {
                Label(path, systemImage: "folder.fill")
                    .lineLimit(1)
                    .truncationMode(.middle)
            } else {
                Text("No folder selected")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Choose…", systemImage: "folder") {
                onChoose()
            }
        }
    }
}
