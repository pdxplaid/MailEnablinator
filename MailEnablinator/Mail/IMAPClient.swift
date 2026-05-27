import Foundation
import Network

actor IMAPClient {
    enum IMAPError: Error, LocalizedError {
        case connectionFailed(String)
        case authenticationFailed
        case commandFailed(String)
        case connectionClosed
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .connectionFailed(let msg): "Connection failed: \(msg)"
            case .authenticationFailed: "Authentication failed. Check username and password."
            case .commandFailed(let msg): "IMAP command failed: \(msg)"
            case .connectionClosed: "Connection closed by server."
            case .invalidResponse: "Unexpected response from server."
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
    private var tagSeq = 0
    var idleTag: String = ""
    private(set) var namespacePrefix = ""

    init(host: String, port: Int, username: String, password: String, useTLS: Bool) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.useTLS = useTLS
    }

    // MARK: - Public API

    func connectAndLogin() async throws {
        try await connect()
        _ = try await readLine()  // server greeting
        let caps = try await fetchCapabilities()
        if caps.contains("AUTH=PLAIN") && !caps.contains("AUTH=LOGIN") {
            try await authenticatePlain()
        } else {
            try await login()
        }
        if caps.contains("NAMESPACE") {
            try await detectNamespace()
        }
    }

    // Returns the server-prefixed folder name (e.g. "INBOX.ME-Processed" on Dreamhost).
    func folderName(_ base: String) -> String { "\(namespacePrefix)\(base)" }

    func disconnect() async {
        conn?.cancel()
        conn = nil
        waiter?.resume(throwing: IMAPError.connectionClosed)
        waiter = nil
    }

    func selectInbox() async throws -> (exists: Int, uidValidity: UInt32) {
        let tag = nextTag()
        try await send("\(tag) SELECT INBOX\r\n")
        var exists = 0
        var uidValidity: UInt32 = 0
        while true {
            let line = try await readLine()
            if line.hasPrefix("* ") {
                if line.contains("EXISTS"), let n = extractNumber(line, before: "EXISTS") { exists = n }
                if line.contains("UIDVALIDITY"), let n = extractUInt32(line, after: "UIDVALIDITY") { uidValidity = n }
            } else if isTaggedOK(line, tag: tag) {
                break
            } else if isTaggedError(line, tag: tag) {
                throw IMAPError.commandFailed(line)
            }
        }
        return (exists, uidValidity)
    }

    func searchUnseen() async throws -> [UInt32] {
        let tag = nextTag()
        try await send("\(tag) UID SEARCH UNSEEN\r\n")
        var uids: [UInt32] = []
        while true {
            let line = try await readLine()
            if line.hasPrefix("* SEARCH") {
                uids = line.dropFirst(9).trimmingCharacters(in: .whitespaces)
                    .components(separatedBy: " ")
                    .compactMap { UInt32($0) }
            } else if isTaggedOK(line, tag: tag) {
                break
            } else if isTaggedError(line, tag: tag) {
                throw IMAPError.commandFailed(line)
            }
        }
        return uids
    }

    func fetchRawMessages(uids: [UInt32]) async throws -> [(uid: UInt32, data: Data)] {
        guard !uids.isEmpty else { return [] }
        let uidSet = uids.map(String.init).joined(separator: ",")
        let tag = nextTag()
        try await send("\(tag) UID FETCH \(uidSet) (FLAGS BODY.PEEK[])\r\n")
        return try await collectFetchResponses(tag: tag)
    }

    func markSeen(uid: UInt32) async throws {
        let tag = nextTag()
        try await send("\(tag) UID STORE \(uid) +FLAGS (\\Seen)\r\n")
        try await drainToTaggedResponse(tag: tag)
    }

    func moveMessage(uid: UInt32, to folder: String) async throws {
        // Try MOVE extension first (RFC 6851); fall back to COPY + delete
        let tag = nextTag()
        try await send("\(tag) UID MOVE \(uid) \"\(folder)\"\r\n")
        let (ok, _) = try await waitForTaggedResponse(tag: tag)
        if !ok {
            // Fallback: COPY + delete
            try await copyAndDelete(uid: uid, to: folder)
        }
    }

    func deleteMessage(uid: UInt32) async throws {
        let tag1 = nextTag()
        try await send("\(tag1) UID STORE \(uid) +FLAGS (\\Deleted)\r\n")
        try await drainToTaggedResponse(tag: tag1)
        let tag2 = nextTag()
        try await send("\(tag2) EXPUNGE\r\n")
        try await drainToTaggedResponse(tag: tag2)
    }

    func ensureFolderExists(_ name: String) async throws {
        let tag = nextTag()
        try await send("\(tag) CREATE \"\(name)\"\r\n")
        // Ignore errors — folder may already exist
        try await drainToTaggedResponse(tag: tag)
    }

    // MARK: - IDLE

    func beginIdle() async throws {
        idleTag = nextTag()
        try await send("\(idleTag) IDLE\r\n")
        let plus = try await readLine()
        guard plus.hasPrefix("+") else { throw IMAPError.commandFailed(plus) }
    }

    // Returns the next untagged response line during IDLE.
    // Caller loops on this to watch for EXISTS.
    func readIdleLine() async throws -> String {
        try await readLine()
    }

    func endIdle() async throws {
        try await send("DONE\r\n")
        try await drainToTaggedResponse(tag: idleTag)
    }

    // MARK: - Connection internals

    private func connect() async throws {
        let params: NWParameters = useTLS ? .tls : .tcp
        let nwHost = NWEndpoint.Host(host)
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            throw IMAPError.connectionFailed("Invalid port \(port)")
        }
        let connection = NWConnection(host: nwHost, port: nwPort, using: params)
        conn = connection

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.stateUpdateHandler = nil
                    cont.resume()
                case .failed(let err):
                    connection.stateUpdateHandler = nil
                    cont.resume(throwing: IMAPError.connectionFailed(err.localizedDescription))
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

    private func pump() {
        guard let connection = conn else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            Task { [self] in
                if let error {
                    await self.failWaiter(error)
                    return
                }
                if let data, !data.isEmpty {
                    await self.appendBuffer(data)
                }
                if isComplete {
                    await self.failWaiter(IMAPError.connectionClosed)
                } else {
                    await self.pump()
                }
            }
        }
    }

    private func appendBuffer(_ data: Data) {
        buf.append(data)
        if let cont = waiter {
            waiter = nil
            cont.resume()
        }
    }

    private func failWaiter(_ error: Error) {
        if let cont = waiter {
            waiter = nil
            cont.resume(throwing: error)
        }
    }

    private func awaitData() async throws {
        guard buf.isEmpty else { return }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            waiter = cont
        }
    }

    func readLine() async throws -> String {
        let crlf = Data([0x0D, 0x0A])
        let lf = Data([0x0A])
        while true {
            // Check for CRLF
            if let range = buf.range(of: crlf) {
                let lineData = buf.subdata(in: 0..<range.lowerBound)
                buf.removeSubrange(0...range.upperBound - 1)
                return String(data: lineData, encoding: .utf8) ?? String(data: lineData, encoding: .isoLatin1) ?? ""
            }
            // Check bare LF (some servers)
            if let range = buf.range(of: lf) {
                let lineData = buf.subdata(in: 0..<range.lowerBound)
                buf.removeSubrange(0...range.upperBound - 1)
                return String(data: lineData, encoding: .utf8)?
                    .trimmingCharacters(in: .init(charactersIn: "\r")) ?? ""
            }
            try await awaitData()
        }
    }

    private func readExactBytes(_ n: Int) async throws -> Data {
        while buf.count < n {
            try await awaitData()
        }
        let result = Data(buf.prefix(n))
        buf.removeFirst(n)
        return result
    }

    private func send(_ text: String) async throws {
        guard let connection = conn else { throw IMAPError.connectionClosed }
        guard let data = text.data(using: .utf8) else { throw IMAPError.invalidResponse }
        return try await withCheckedThrowingContinuation { cont in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            })
        }
    }

    // MARK: - IMAP protocol helpers

    private func detectNamespace() async throws {
        let tag = nextTag()
        try await send("\(tag) NAMESPACE\r\n")
        while true {
            let line = try await readLine()
            if line.hasPrefix("* NAMESPACE") {
                // First quoted string in the personal namespace list is the prefix.
                // e.g. * NAMESPACE (("INBOX." ".")) NIL NIL  →  prefix = "INBOX."
                if let match = line.firstMatch(of: /\(\("([^"]*)/) {
                    namespacePrefix = String(match.output.1)
                }
            } else if isTaggedOK(line, tag: tag) { break }
            else if isTaggedError(line, tag: tag) { break }
        }
    }

    private func fetchCapabilities() async throws -> Set<String> {
        let tag = nextTag()
        try await send("\(tag) CAPABILITY\r\n")
        var caps = Set<String>()
        while true {
            let line = try await readLine()
            if line.hasPrefix("* CAPABILITY") {
                caps = Set(line.dropFirst(13).components(separatedBy: " ").map { $0.uppercased() })
            } else if isTaggedOK(line, tag: tag) { break }
            else if isTaggedError(line, tag: tag) { break }
        }
        return caps
    }

    private func authenticatePlain() async throws {
        let tag = nextTag()
        let raw = "\0\(username)\0\(password)"
        let encoded = Data(raw.utf8).base64EncodedString()
        try await send("\(tag) AUTHENTICATE PLAIN \(encoded)\r\n")
        let (ok, line) = try await waitForTaggedResponse(tag: tag)
        if !ok { throw IMAPError.commandFailed(line) }
    }

    private func login() async throws {
        let tag = nextTag()
        let escapedUser = username.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"")
        let escapedPass = password.replacing("\\", with: "\\\\").replacing("\"", with: "\\\"")
        try await send("\(tag) LOGIN \"\(escapedUser)\" \"\(escapedPass)\"\r\n")
        let (ok, line) = try await waitForTaggedResponse(tag: tag)
        if !ok {
            throw IMAPError.commandFailed(line)
        }
    }

    private func collectFetchResponses(tag: String) async throws -> [(uid: UInt32, data: Data)] {
        var results: [(uid: UInt32, data: Data)] = []
        while true {
            let line = try await readLine()
            if isTaggedOK(line, tag: tag) { break }
            if isTaggedError(line, tag: tag) { throw IMAPError.commandFailed(line) }
            guard line.hasPrefix("*"), line.contains("FETCH") else { continue }

            // Parse UID from the FETCH header line
            var uid: UInt32 = 0
            if let u = extractUInt32AfterKeyword("UID", in: line) { uid = u }

            // Parse literal size if present: {N}
            if let sizeMatch = line.firstMatch(of: /\{(\d+)\}/) {
                let size = Int(sizeMatch.output.1) ?? 0
                let msgData = try await readExactBytes(size)
                _ = try await readLine()  // closing ")"
                if uid > 0 { results.append((uid, msgData)) }
            }
        }
        return results
    }

    private func drainToTaggedResponse(tag: String) async throws {
        while true {
            let line = try await readLine()
            if isTaggedOK(line, tag: tag) { return }
            if isTaggedError(line, tag: tag) { throw IMAPError.commandFailed(line) }
        }
    }

    private func waitForTaggedResponse(tag: String) async throws -> (Bool, String) {
        while true {
            let line = try await readLine()
            if isTaggedOK(line, tag: tag) { return (true, line) }
            if isTaggedError(line, tag: tag) { return (false, line) }
        }
    }

    private func copyAndDelete(uid: UInt32, to folder: String) async throws {
        let tag1 = nextTag()
        try await send("\(tag1) UID COPY \(uid) \"\(folder)\"\r\n")
        try await drainToTaggedResponse(tag: tag1)
        try await deleteMessage(uid: uid)
    }

    private func nextTag() -> String {
        tagSeq += 1
        return "ME\(tagSeq)"
    }

    // MARK: - Response parsing utilities

    private func isTaggedOK(_ line: String, tag: String) -> Bool {
        line.hasPrefix("\(tag) OK")
    }

    private func isTaggedError(_ line: String, tag: String) -> Bool {
        line.hasPrefix("\(tag) NO") || line.hasPrefix("\(tag) BAD")
    }

    private func extractNumber(_ line: String, before keyword: String) -> Int? {
        guard let kwRange = line.range(of: keyword) else { return nil }
        let before = line[..<kwRange.lowerBound].trimmingCharacters(in: .whitespaces)
        let parts = before.components(separatedBy: " ")
        return parts.last.flatMap(Int.init)
    }

    private func extractUInt32(_ line: String, after keyword: String) -> UInt32? {
        guard let kwRange = line.range(of: keyword) else { return nil }
        let after = line[kwRange.upperBound...].trimmingCharacters(in: .whitespaces)
        return UInt32(after.components(separatedBy: CharacterSet.whitespaces.union(.init(charactersIn: ")([]{}"))).first ?? "")
    }

    private func extractUInt32AfterKeyword(_ keyword: String, in line: String) -> UInt32? {
        let escaped = NSRegularExpression.escapedPattern(for: keyword)
        guard let regex = try? NSRegularExpression(pattern: "\(escaped)\\s+(\\d+)"),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range(at: 1), in: line) else { return nil }
        return UInt32(line[range])
    }
}
