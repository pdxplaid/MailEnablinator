import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    let allowedUsersStore = AllowedUsersStore()
    let destinationStore = DestinationStore()
    let mailAccountStore = MailAccountStore()
    let repliesStore = RepliesStore()
    let activityLog = ActivityLogStore()

    private(set) var connectionState: ConnectionState = .disconnected
    private var mailEngine: MailEngine?
    private var engineTask: Task<Void, Never>?

    var menuBarIcon: String {
        switch connectionState {
        case .disconnected: "envelope.fill"
        case .connecting: "envelope.badge"
        case .idle: "envelope"
        case .processing: "envelope.open"
        case .error: "envelope.badge.fill"
        }
    }

    var isConnected: Bool {
        connectionState == .idle || connectionState == .processing
    }

    init() {
        startEngine()
    }

    func startEngine() {
        guard mailAccountStore.isConfigured else { return }
        let engine = MailEngine(
            accountStore: mailAccountStore,
            allowedUsersStore: allowedUsersStore,
            destinationStore: destinationStore,
            repliesStore: repliesStore,
            activityLog: activityLog
        )
        mailEngine = engine
        engineTask?.cancel()
        engineTask = Task { [weak self] in
            guard let self else { return }
            for await state in await engine.stateUpdates() {
                connectionState = state
            }
        }
        Task { await engine.run() }
    }

    func restartEngine() {
        engineTask?.cancel()
        engineTask = nil
        mailEngine = nil
        connectionState = .disconnected
        startEngine()
    }

    func checkNow() async {
        await mailEngine?.checkNow()
    }
}
