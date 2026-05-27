import Foundation

actor MailEngine {
    private let accountStore: MailAccountStore
    private let allowedUsersStore: AllowedUsersStore
    private let destinationStore: DestinationStore
    private let repliesStore: RepliesStore
    private let activityLog: ActivityLogStore

    private var imap: IMAPClient?
    private var smtp: SMTPClient?

    private let (stateStream, stateContinuation) = AsyncStream<ConnectionState>.makeStream()

    // Used to interrupt IDLE from checkNow()
    private var idleInterrupt: CheckedContinuation<Bool, Error>?
    private var idleReadTask: Task<Void, Never>?
    private var idleTimeoutTask: Task<Void, Never>?

    private var lastProcessedUID: UInt32 {
        get { UInt32(UserDefaults.standard.integer(forKey: "imap.lastProcessedUID")) }
        set { UserDefaults.standard.set(Int(newValue), forKey: "imap.lastProcessedUID") }
    }

    init(
        accountStore: MailAccountStore,
        allowedUsersStore: AllowedUsersStore,
        destinationStore: DestinationStore,
        repliesStore: RepliesStore,
        activityLog: ActivityLogStore
    ) {
        self.accountStore = accountStore
        self.allowedUsersStore = allowedUsersStore
        self.destinationStore = destinationStore
        self.repliesStore = repliesStore
        self.activityLog = activityLog
    }

    func stateUpdates() -> AsyncStream<ConnectionState> { stateStream }

    // Main run loop — call in a Task from AppState
    func run() async {
        var backoff: Double = 1
        while !Task.isCancelled {
            stateContinuation.yield(.connecting)
            await log("Connecting to \(await accountStore.imapHost)…")
            do {
                try await buildClients()
                guard let imap else { return }
                try await imap.connectAndLogin()
                await log("Connected. Syncing inbox…", level: .success)
                _ = try await imap.selectInbox()
                try await ensureSystemFolders(imap)
                try await sync(imap)
                backoff = 1
                try await idleLoop(imap)
            } catch is CancellationError {
                break
            } catch {
                await log("Error: \(error.localizedDescription)", level: .error)
                stateContinuation.yield(.error(error.localizedDescription))
                do { try await Task.sleep(for: .seconds(backoff)) } catch { break }
                backoff = min(backoff * 2, 30)
            }
        }
        await imap?.disconnect()
        stateContinuation.yield(.disconnected)
        stateContinuation.finish()
    }

    // Called from AppState to force an immediate check
    func checkNow() {
        let cont = idleInterrupt
        idleInterrupt = nil
        idleReadTask?.cancel()
        idleTimeoutTask?.cancel()
        cont?.resume(returning: true)
    }

    // MARK: - Private

    private func buildClients() async {
        let host = await accountStore.imapHost
        let port = await accountStore.imapPort
        let user = await accountStore.imapUsername
        let pass = KeychainStore.load(for: .imapPassword) ?? ""
        let tls = await accountStore.imapUseTLS
        imap = IMAPClient(host: host, port: port, username: user, password: pass, useTLS: tls)

        let sHost = await accountStore.smtpHost
        let sPort = await accountStore.smtpPort
        let sUser = await accountStore.smtpUsername
        let sPass = KeychainStore.load(for: .smtpPassword) ?? ""
        let sTLS = await accountStore.smtpUseTLS
        smtp = SMTPClient(host: sHost, port: sPort, username: sUser, password: sPass, useTLS: sTLS)
    }

    private func ensureSystemFolders(_ imap: IMAPClient) async throws {
        try await imap.ensureFolderExists(imap.folderName("ME-Processed"))
        try await imap.ensureFolderExists(imap.folderName("ME-Rejected"))
    }

    private func sync(_ imap: IMAPClient) async throws {
        let unseenUIDs = try await imap.searchUnseen()
        let toProcess = unseenUIDs.filter { $0 > lastProcessedUID }
        guard !toProcess.isEmpty else {
            await log("Inbox up to date.")
            return
        }
        await log("Processing \(toProcess.count) new message(s)…")
        try await fetchAndProcess(uids: toProcess, imap: imap)
    }

    private func idleLoop(_ imap: IMAPClient) async throws {
        while !Task.isCancelled {
            stateContinuation.yield(.idle)
            await log("Watching for new mail (IDLE).")
            try await imap.beginIdle()
            let hasNewMail = try await waitForIDLEEvent(imap)
            try await imap.endIdle()

            if hasNewMail {
                stateContinuation.yield(.processing)
                _ = try await imap.selectInbox()
                try await sync(imap)
            }
        }
    }

    // Returns true if new mail was detected (EXISTS), false on timeout / checkNow
    private func waitForIDLEEvent(_ imap: IMAPClient) async throws -> Bool {
        try await withCheckedThrowingContinuation { cont in
            idleInterrupt = cont

            idleReadTask = Task { [weak self] in
                guard let self else { return }
                while !Task.isCancelled {
                    do {
                        let line = try await imap.readIdleLine()
                        if line.contains("EXISTS") {
                            let stored = await self.consumeIdleInterrupt()
                            stored?.resume(returning: true)
                            return
                        }
                    } catch {
                        let stored = await self.consumeIdleInterrupt()
                        stored?.resume(throwing: error)
                        return
                    }
                }
            }

            idleTimeoutTask = Task { [weak self] in
                guard let self else { return }
                do {
                    // RFC 2177 recommends re-IDLEing every 29 min
                    try await Task.sleep(for: .seconds(25 * 60))
                    let stored = await self.consumeIdleInterrupt()
                    stored?.resume(returning: false)
                } catch {
                    // Cancelled externally
                }
            }
        }
    }

    private func consumeIdleInterrupt() -> CheckedContinuation<Bool, Error>? {
        let cont = idleInterrupt
        idleInterrupt = nil
        idleReadTask?.cancel()
        idleReadTask = nil
        idleTimeoutTask?.cancel()
        idleTimeoutTask = nil
        return cont
    }

    private func fetchAndProcess(uids: [UInt32], imap: IMAPClient) async throws {
        let rawMessages = try await imap.fetchRawMessages(uids: uids)
        for (uid, data) in rawMessages {
            let message = MIMEParser.parse(data, uid: uid)
            try await processMessage(message, imap: imap)
            if uid > lastProcessedUID { lastProcessedUID = uid }
        }
    }

    private func processMessage(_ message: MailMessage, imap: IMAPClient) async throws {
        let allowedEmails = await allowedUsersStore.addresses
        let defaultRmTag = await destinationStore.defaultRmTag
        let deleteAfter = await accountStore.deleteAfterProcessing
        let outcome = MailProcessor.process(
            message: message,
            allowedEmails: allowedEmails,
            defaultRmTag: defaultRmTag,
            deleteAfterProcessing: deleteAfter
        )

        switch outcome {
        case .reject:
            await log("Rejected email from unknown sender: \(message.from)")
            try await imap.moveMessage(uid: message.uid, to: imap.folderName("ME-Rejected"))

        case .sendReply(let replyKey):
            let body = await replyBody(for: replyKey)
            await sendReplyIfPossible(to: message.from, subject: "Re: \(message.subject)", body: body, inReplyTo: message.messageID)
            await log("Sent reply to \(message.from): \(replyKey)", level: .info)
            try await applyServerAction(uid: message.uid, delete: deleteAfter, imap: imap)

        case .processImages(let inputs, let replyKey):
            guard let destFolder = await destinationStore.resolveDestination() else {
                await log("No destination folder configured — skipping image save.", level: .warning)
                return
            }
            let didScope = destFolder.startAccessingSecurityScopedResource()
            defer { if didScope { destFolder.stopAccessingSecurityScopedResource() } }

            for input in inputs {
                do {
                    try await Task.detached(priority: .userInitiated) {
                        try ImageImporter.importImage(ImageImporter.Input(
                            imageData: input.attachment.data,
                            filename: input.attachment.filename,
                            title: input.title,
                            caption: input.caption,
                            keywords: input.keywords,
                            finderTags: input.finderTags,
                            destinationFolder: destFolder
                        ))
                    }.value
                    await log("Saved \(input.attachment.filename) — \(input.title)", level: .success)
                } catch {
                    await log("Failed to save \(input.attachment.filename): \(error.localizedDescription)", level: .error)
                }
            }

            if let replyKey {
                let body = await replyBody(for: replyKey)
                await sendReplyIfPossible(to: message.from, subject: "Re: \(message.subject)", body: body, inReplyTo: message.messageID)
            }
            try await applyServerAction(uid: message.uid, delete: deleteAfter, imap: imap)
        }
    }

    private func applyServerAction(uid: UInt32, delete: Bool, imap: IMAPClient) async throws {
        if delete {
            try await imap.deleteMessage(uid: uid)
        } else {
            try await imap.markSeen(uid: uid)
            try await imap.moveMessage(uid: uid, to: imap.folderName("ME-Processed"))
        }
    }

    private func replyBody(for key: String) async -> String {
        switch key {
        case "no-image": return await repliesStore.noImageReply
        case "non-image": return await repliesStore.nonImageReply
        case "mixed": return await repliesStore.mixedReply
        default: return ""
        }
    }

    private func sendReplyIfPossible(to: String, subject: String, body: String, inReplyTo: String?) async {
        guard let smtp else { return }
        let from = await accountStore.imapUsername
        do {
            try await smtp.sendReply(from: from, to: to, subject: subject, body: body, inReplyTo: inReplyTo)
        } catch {
            await log("Failed to send reply to \(to): \(error.localizedDescription)", level: .warning)
        }
    }

    private func log(_ message: String, level: ActivityLogEntry.Level = .info) async {
        await activityLog.add(message, level: level)
    }
}
