import Foundation
import Observation

@MainActor
@Observable
final class AllowedUsersStore {
    private enum Key {
        static let addresses = "allowedUserAddresses"
    }

    private(set) var addresses: [String] = []

    init() {
        addresses = UserDefaults.standard.stringArray(forKey: Key.addresses) ?? []
    }

    func add(_ email: String) {
        let normalized = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !addresses.contains(normalized) else { return }
        addresses.append(normalized)
        persist()
    }

    func remove(atOffsets offsets: IndexSet) {
        for offset in offsets.reversed() {
            addresses.remove(at: offset)
        }
        persist()
    }

    func isAllowed(_ email: String) -> Bool {
        addresses.contains(email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func persist() {
        UserDefaults.standard.set(addresses, forKey: Key.addresses)
    }
}
