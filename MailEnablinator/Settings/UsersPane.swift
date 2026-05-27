import SwiftUI

struct UsersPane: View {
    @Environment(AppState.self) private var appState
    @State private var newEmail = ""
    @State private var showValidationError = false

    private var store: AllowedUsersStore { appState.allowedUsersStore }

    var body: some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                Text("Allowed Senders")
                    .font(.headline)
                Text("Emails from senders not on this list are silently moved to ME-Rejected.")
                    .foregroundStyle(.secondary)
            }
            .padding([.horizontal, .top])

            List {
                ForEach(store.addresses, id: \.self) { address in
                    HStack {
                        Text(address)
                        Spacer()
                        Button("Remove", role: .destructive) {
                            if let idx = store.addresses.firstIndex(of: address) {
                                store.remove(atOffsets: IndexSet(integer: idx))
                            }
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                    }
                }
            }

            HStack {
                TextField("email@example.com", text: $newEmail)
                    .textContentType(.emailAddress)
                    .onSubmit { addEmail() }
                Button("Add", systemImage: "plus") { addEmail() }
            }
            .padding([.horizontal, .bottom])

            if showValidationError {
                Text("Please enter a valid email address.")
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }
        }
    }

    private func addEmail() {
        guard isValidEmail(newEmail) else {
            showValidationError = true
            return
        }
        showValidationError = false
        store.add(newEmail)
        newEmail = ""
    }

    private func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("@") && trimmed.contains(".")
    }
}
