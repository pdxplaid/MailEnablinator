import SwiftUI

struct MailAccountPane: View {
    @Environment(AppState.self) private var appState
    @State private var imapPassword = ""
    @State private var smtpPassword = ""
    @State private var connectionStatus: ConnectionTestStatus = .idle

    private var store: MailAccountStore { appState.mailAccountStore }

    var body: some View {
        Form {
            Section("IMAP (Incoming)") {
                TextField(
                    "Server",
                    text: Binding(get: { store.imapHost }, set: { store.imapHost = $0 })
                )
                TextField(
                    "Port",
                    value: Binding(get: { store.imapPort }, set: { store.imapPort = $0 }),
                    format: .number
                )
                TextField(
                    "Username",
                    text: Binding(get: { store.imapUsername }, set: { store.imapUsername = $0 })
                )
                .textContentType(.username)
                SecureField("Password", text: $imapPassword)
                    .onSubmit { KeychainStore.save(imapPassword, for: .imapPassword) }
                Toggle(
                    "Use TLS",
                    isOn: Binding(get: { store.imapUseTLS }, set: { store.imapUseTLS = $0 })
                )
            }

            Section("SMTP (Outgoing)") {
                TextField(
                    "Server",
                    text: Binding(get: { store.smtpHost }, set: { store.smtpHost = $0 })
                )
                TextField(
                    "Port",
                    value: Binding(get: { store.smtpPort }, set: { store.smtpPort = $0 }),
                    format: .number
                )
                TextField(
                    "Username",
                    text: Binding(get: { store.smtpUsername }, set: { store.smtpUsername = $0 })
                )
                .textContentType(.username)
                SecureField("Password", text: $smtpPassword)
                    .onSubmit { KeychainStore.save(smtpPassword, for: .smtpPassword) }
                Toggle(
                    "Use Implicit TLS (SMTPS, port 465)",
                    isOn: Binding(
                        get: { store.smtpUseTLS },
                        set: { newValue in
                            store.smtpUseTLS = newValue
                            // Auto-suggest the canonical port when toggling TLS
                            store.smtpPort = newValue ? 465 : 587
                        }
                    )
                )
                if !store.smtpUseTLS {
                    Text("Note: STARTTLS (port 587) is not supported. Enable implicit TLS and use port 465.")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }

            Section("Processing") {
                Toggle(
                    "Delete messages after processing",
                    isOn: Binding(get: { store.deleteAfterProcessing }, set: { store.deleteAfterProcessing = $0 })
                )
                Text("When off, processed messages are marked read and moved to ME-Processed.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section {
                HStack {
                    Button("Test Connection") {
                        Task { await testConnection() }
                    }
                    .disabled(connectionStatus == .testing)
                    connectionStatusView
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            imapPassword = KeychainStore.load(for: .imapPassword) ?? ""
            smtpPassword = KeychainStore.load(for: .smtpPassword) ?? ""
        }
        .onChange(of: appState.connectionState) { _, _ in
            if connectionStatus == .testing { connectionStatus = .idle }
        }
    }

    @ViewBuilder
    private var connectionStatusView: some View {
        switch connectionStatus {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView()
                .controlSize(.small)
        case .success:
            Label("Connected", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failure(let msg):
            Label(msg, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private func testConnection() async {
        // Persist whatever is currently in the fields before testing
        KeychainStore.save(imapPassword, for: .imapPassword)
        KeychainStore.save(smtpPassword, for: .smtpPassword)
        connectionStatus = .testing
        do {
            let imap = IMAPClient(
                host: store.imapHost,
                port: store.imapPort,
                username: store.imapUsername,
                password: imapPassword,
                useTLS: store.imapUseTLS
            )
            try await imap.connectAndLogin()
            await imap.disconnect()
            connectionStatus = .success
        } catch {
            connectionStatus = .failure(error.localizedDescription)
        }
    }
}
