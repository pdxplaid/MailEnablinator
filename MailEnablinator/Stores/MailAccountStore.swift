import Foundation
import Observation

@MainActor
@Observable
final class MailAccountStore {
    private enum Keys {
        static let imapHost = "imapHost"
        static let imapPort = "imapPort"
        static let imapUsername = "imapUsername"
        static let imapUseTLS = "imapUseTLS"
        static let smtpHost = "smtpHost"
        static let smtpPort = "smtpPort"
        static let smtpUsername = "smtpUsername"
        static let smtpUseTLS = "smtpUseTLS"
        static let deleteAfterProcessing = "deleteAfterProcessing"
    }

    var imapHost: String {
        get { UserDefaults.standard.string(forKey: Keys.imapHost) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.imapHost) }
    }

    var imapPort: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: Keys.imapPort)
            return v == 0 ? 993 : v
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.imapPort) }
    }

    var imapUsername: String {
        get { UserDefaults.standard.string(forKey: Keys.imapUsername) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.imapUsername) }
    }

    var imapUseTLS: Bool {
        get {
            guard UserDefaults.standard.object(forKey: Keys.imapUseTLS) != nil else { return true }
            return UserDefaults.standard.bool(forKey: Keys.imapUseTLS)
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.imapUseTLS) }
    }

    var smtpHost: String {
        get { UserDefaults.standard.string(forKey: Keys.smtpHost) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.smtpHost) }
    }

    var smtpPort: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: Keys.smtpPort)
            return v == 0 ? 465 : v
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.smtpPort) }
    }

    var smtpUsername: String {
        get { UserDefaults.standard.string(forKey: Keys.smtpUsername) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.smtpUsername) }
    }

    // true = implicit TLS (SMTPS, port 465); false = STARTTLS (port 587)
    var smtpUseTLS: Bool {
        get {
            guard UserDefaults.standard.object(forKey: Keys.smtpUseTLS) != nil else { return true }
            return UserDefaults.standard.bool(forKey: Keys.smtpUseTLS)
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.smtpUseTLS) }
    }

    var deleteAfterProcessing: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.deleteAfterProcessing) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.deleteAfterProcessing) }
    }

    var isConfigured: Bool {
        !imapHost.isEmpty && !imapUsername.isEmpty
    }
}
