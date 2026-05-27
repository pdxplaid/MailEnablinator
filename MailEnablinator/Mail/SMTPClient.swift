import Foundation
import Network

// Sends reply emails over SMTP with implicit TLS (SMTPS, port 465).
// STARTTLS (port 587) is not supported in v1.
actor SMTPClient {
    enum SMTPError: Error, LocalizedError {
        case connectionFailed(String)
        case authenticationFailed
        case commandRejected(String)
        case connectionClosed

        var errorDescription: String? {
            switch self {
            case .connectionFailed(let msg): "SMTP connection failed: \(msg)"
            case .authenticationFailed: "SMTP authentication failed."
            case .commandRejected(let msg): "SMTP command rejected: \(msg)"
            case .connectionClosed: "SMTP connection closed."
            }
        }
    }

    let host: String
    let port: Int
    let username: String
    let password: String
    let useTLS: Bool

    private var conn: NWConnection?
    private var buf = Data()
    private var waiter: CheckedContinuation<Void, Error>?

    init(host: String, port: Int, username: String, password: String, useTLS: Bool) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.useTLS = useTLS
    }

    // MARK: - Public API

    func sendReply(
        from: String,
        to: String,
        subject: String,
        body: String,
        inReplyTo: String?
    ) async throws {
        smtpLog("Connecting to \(host):\(port) (TLS: \(useTLS))")
        try await connect()
        defer { Task { self.disconnect() } }

        let greeting = try await readLine()
        smtpLog("← \(greeting)")
        try await ehlo()
        try await authLogin()
        try await mailFrom(from)
        try await rcptTo(to)
        try await sendData(buildMessage(from: from, to: to, subject: subject, body: body, inReplyTo: inReplyTo))
        try await quit()
        smtpLog("Done.")
    }

    // MARK: - SMTP commands

    private func ehlo() async throws {
        smtpLog("→ EHLO")
        try await send("EHLO mailEnablinator\r\n")
        while true {
            let line = try await readLine()
            smtpLog("← \(line)")
            if line.hasPrefix("250 ") { break }
            if !line.hasPrefix("250-") { throw SMTPError.commandRejected(line) }
        }
    }

    private func authLogin() async throws {
        smtpLog("→ AUTH LOGIN")
        try await send("AUTH LOGIN\r\n")
        let r1 = try await readLine()
        smtpLog("← \(r1)")
        guard r1.hasPrefix("334") else { throw SMTPError.commandRejected(r1) }
        try await send(base64(username) + "\r\n")
        let r2 = try await readLine()
        smtpLog("← \(r2)")
        guard r2.hasPrefix("334") else { throw SMTPError.commandRejected(r2) }
        try await send(base64(password) + "\r\n")
        let r3 = try await readLine()
        smtpLog("← \(r3)")
        guard r3.hasPrefix("235") else { throw SMTPError.authenticationFailed }
        smtpLog("Auth OK")
    }

    private func mailFrom(_ address: String) async throws {
        smtpLog("→ MAIL FROM:<\(address)>")
        try await send("MAIL FROM:<\(address)>\r\n")
        let r = try await readLine()
        smtpLog("← \(r)")
        guard r.hasPrefix("250") else { throw SMTPError.commandRejected(r) }
    }

    private func rcptTo(_ address: String) async throws {
        smtpLog("→ RCPT TO:<\(address)>")
        try await send("RCPT TO:<\(address)>\r\n")
        let r = try await readLine()
        smtpLog("← \(r)")
        guard r.hasPrefix("250") else { throw SMTPError.commandRejected(r) }
    }

    private func sendData(_ message: String) async throws {
        smtpLog("→ DATA (\(message.utf8.count) bytes)")
        try await send("DATA\r\n")
        let r1 = try await readLine()
        smtpLog("← \(r1)")
        guard r1.hasPrefix("354") else { throw SMTPError.commandRejected(r1) }
        let stuffed = message.components(separatedBy: "\r\n")
            .map { $0.hasPrefix(".") ? ".\($0)" : $0 }
            .joined(separator: "\r\n")
        try await send(stuffed + "\r\n.\r\n")
        let r2 = try await readLine()
        smtpLog("← \(r2)")
        guard r2.hasPrefix("250") else { throw SMTPError.commandRejected(r2) }
    }

    private func quit() async throws {
        smtpLog("→ QUIT")
        try await send("QUIT\r\n")
        _ = try? await readLine()
    }

    private func smtpLog(_ msg: String) {
        print("[SMTP] \(msg)")
    }

    // MARK: - Message building

    private func buildMessage(from: String, to: String, subject: String, body: String, inReplyTo: String?) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        let bodyData = body.data(using: .utf8) ?? Data()
        let bodyB64 = bodyData.base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn])
        var headers = """
Date: \(dateFormatter.string(from: .now))\r\nFrom: <\(from)>\r\nTo: <\(to)>\r\nSubject: \(subject)\r\nMessage-ID: <\(UUID().uuidString)@mailEnablinator>\r\nMIME-Version: 1.0\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Transfer-Encoding: base64\r\n
"""
        if let replyID = inReplyTo { headers += "In-Reply-To: \(replyID)\r\nReferences: \(replyID)\r\n" }
        return headers + "\r\n" + bodyB64
    }

    // MARK: - Connection

    private func connect() async throws {
        let params: NWParameters = useTLS ? .tls : .tcp
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw SMTPError.connectionFailed("Invalid port \(port)")
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: params)
        conn = connection

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.stateUpdateHandler = nil
                    cont.resume()
                case .failed(let err):
                    connection.stateUpdateHandler = nil
                    cont.resume(throwing: SMTPError.connectionFailed(err.localizedDescription))
                case .cancelled:
                    connection.stateUpdateHandler = nil
                    cont.resume(throwing: CancellationError())
                default:
                    break
                }
            }
            connection.start(queue: .global(qos: .utility))
        }

        pump()
    }

    private func disconnect() {
        conn?.cancel()
        conn = nil
        waiter?.resume(throwing: SMTPError.connectionClosed)
        waiter = nil
    }

    private func pump() {
        guard let connection = conn else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            Task { [self] in
                if let error { await self.failWaiter(error); return }
                if let data, !data.isEmpty { await self.appendBuffer(data) }
                if isComplete { await self.failWaiter(SMTPError.connectionClosed) } else { await self.pump() }
            }
        }
    }

    private func appendBuffer(_ data: Data) {
        buf.append(data)
        if let cont = waiter { waiter = nil; cont.resume() }
    }

    private func failWaiter(_ error: Error) {
        if let cont = waiter { waiter = nil; cont.resume(throwing: error) }
    }

    private func awaitData() async throws {
        // Always suspend — see IMAPClient for explanation.
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            waiter = cont
        }
    }

    private func readLine() async throws -> String {
        let crlf = Data([0x0D, 0x0A])
        while true {
            if let range = buf.range(of: crlf) {
                let lineData = Data(buf[buf.startIndex..<range.lowerBound])
                buf = Data(buf[range.upperBound...])   // resets startIndex to 0
                return String(data: lineData, encoding: .utf8) ?? ""
            }
            try await awaitData()
        }
    }

    private func send(_ text: String) async throws {
        guard let connection = conn else { throw SMTPError.connectionClosed }
        guard let data = text.data(using: .utf8) else { return }
        return try await withCheckedThrowingContinuation { cont in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }

    private func base64(_ string: String) -> String {
        (string.data(using: .utf8) ?? Data()).base64EncodedString()
    }
}
