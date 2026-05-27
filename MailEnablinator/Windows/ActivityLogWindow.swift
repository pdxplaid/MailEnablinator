import SwiftUI
import UniformTypeIdentifiers

struct ActivityLogWindow: View {
    @Environment(AppState.self) private var appState
    @State private var isExportingLog = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(appState.activityLog.entries) { entry in
                            ActivityLogRow(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(8)
                }
                .scrollIndicators(.hidden)
                .onChange(of: appState.activityLog.entries.count) { _, _ in
                    if let last = appState.activityLog.entries.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Save Log…") { isExportingLog = true }
                    .buttonStyle(.borderless)
                    .disabled(appState.activityLog.entries.isEmpty)
                    .padding(.vertical, 8)
                Button("Clear Log") { appState.activityLog.clear() }
                    .buttonStyle(.borderless)
                    .padding(8)
            }
        }
        .fileExporter(
            isPresented: $isExportingLog,
            document: ExportableLog(entries: appState.activityLog.entries),
            contentType: .plainText,
            defaultFilename: exportFilename
        ) { _ in }
    }

    private var exportFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "MailEnablinator-Log-\(formatter.string(from: .now)).txt"
    }
}
