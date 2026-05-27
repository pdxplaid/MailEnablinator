import SwiftUI

struct ActivityLogWindow: View {
    @Environment(AppState.self) private var appState

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
                Button("Clear Log") { appState.activityLog.clear() }
                    .buttonStyle(.borderless)
                    .padding(8)
            }
        }
    }
}
