import Foundation

actor DestinationCuller {
    private let store: DestinationStore
    private let activityLog: ActivityLogStore
    private let watcher = FolderWatcher()
    private var watcherTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var inFlight = false

    init(store: DestinationStore, activityLog: ActivityLogStore) {
        self.store = store
        self.activityLog = activityLog
    }

    func start() {
        let store = self.store
        let watcher = self.watcher

        // Watch the destination folder for filesystem events (catches iCloud, Finder, and this app).
        watcherTask = Task { [weak self] in
            guard let self else { return }
            if let destURL = await store.resolveDestination() {
                watcher.start(url: destURL)
            }
            for await _ in watcher.changes {
                await self.triggerEvaluate()
            }
        }

        // Timer: re-evaluate periodically so deadline-based rules fire even without FS events.
        timerTask = Task.detached(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let interval = await store.cullInterval
                try? await Task.sleep(for: .seconds(interval.seconds))
                if Task.isCancelled { break }
                await self.triggerEvaluate()
            }
        }

        // First pass at launch so overdue files aren't stuck until the first tick.
        Task { await self.triggerEvaluate() }
    }

    func stop() {
        watcherTask?.cancel()
        timerTask?.cancel()
        watcherTask = nil
        timerTask = nil
        watcher.stop()
    }

    func restart() {
        stop()
        start()
    }

    func cullNow() {
        triggerEvaluate()
    }

    // MARK: - Private

    private func triggerEvaluate() {
        guard !inFlight else { return }
        inFlight = true
        let store = self.store
        let activityLog = self.activityLog
        Task.detached(priority: .utility) { [weak self] in
            await DestinationCuller.performEvaluate(store: store, activityLog: activityLog)
            await self?.didFinishEvaluate()
        }
    }

    private func didFinishEvaluate() {
        inFlight = false
    }

    // Runs entirely off the main actor. Reads store config with brief @MainActor hops,
    // then does all file I/O on the cooperative thread pool.
    private nonisolated static func performEvaluate(
        store: DestinationStore,
        activityLog: ActivityLogStore
    ) async {
        let destURL      = await store.resolveDestination()
        let archiveURL   = await store.resolveArchive()
        let defaultTag   = await store.defaultRmTag
        let useDateSubs  = await store.archiveUseDateSubfolders

        guard let destURL else { return }

        let didScopeDest = destURL.startAccessingSecurityScopedResource()
        defer { if didScopeDest { destURL.stopAccessingSecurityScopedResource() } }

        let didScopeArchive = archiveURL.map { $0.startAccessingSecurityScopedResource() } ?? false
        defer { if didScopeArchive { archiveURL?.stopAccessingSecurityScopedResource() } }

        let contents: [URL]
        do {
            contents = try FileManager.default.contentsOfDirectory(
                at: destURL,
                includingPropertiesForKeys: [.isDirectoryKey, .addedToDirectoryDateKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )
        } catch {
            await activityLog.add(
                "Culler: could not read destination folder — \(error.localizedDescription)",
                level: .error
            )
            return
        }

        let now = Date.now

        for fileURL in contents {
            let vals = try? fileURL.resourceValues(forKeys: [.isDirectoryKey, .addedToDirectoryDateKey])
            if vals?.isDirectory == true { continue }
            let addedDate = vals?.addedToDirectoryDate ?? now

            // Read Finder tags (strips Finder color-index suffix internally in RmTagParser).
            var tags = FinderTags.read(at: fileURL)

            // Find the first Rm* tag.
            var rmTagStr = tags.first(where: { RmTagParser.isRmTag($0) })

            // No Rm* tag and file is an image → merge IPTC Keywords into Finder tags.
            if rmTagStr == nil {
                let iptcWords = IPTCKeywordReader.keywords(at: fileURL)
                if !iptcWords.isEmpty {
                    let merged = mergeUnion(existing: tags, new: iptcWords)
                    if merged != tags {
                        FinderTags.apply(merged, to: fileURL)
                        tags = merged
                    }
                    rmTagStr = tags.first(where: { RmTagParser.isRmTag($0) })
                }
            }

            // Still no Rm* tag → apply default in memory only (do not write back to file).
            let effectiveTag = rmTagStr ?? defaultTag.rawValue

            guard let rule = RmTagParser.parse(effectiveTag) else { continue }
            guard let dueDate = rule.dueDate(addedAt: addedDate) else {
                // RmManual — skip forever.
                continue
            }
            guard now >= dueDate else { continue }

            guard let archiveURL else {
                await activityLog.add(
                    "Culler: '\(fileURL.lastPathComponent)' is due but no archive folder is configured.",
                    level: .warning
                )
                continue
            }

            do {
                let dest = try ArchiveMover.move(
                    fileURL,
                    to: archiveURL,
                    addedDate: addedDate,
                    useDateSubfolder: useDateSubs
                )
                await activityLog.add(
                    "Archived '\(fileURL.lastPathComponent)' → '\(dest.lastPathComponent)'",
                    level: .success
                )
            } catch {
                await activityLog.add(
                    "Culler: failed to archive '\(fileURL.lastPathComponent)' — \(error.localizedDescription)",
                    level: .error
                )
            }
        }
    }

    // Union merge: existing tags first, then new items not already present (case-insensitive).
    private nonisolated static func mergeUnion(existing: [String], new: [String]) -> [String] {
        let seen = Set(existing.map { $0.lowercased() })
        return existing + new.filter { !seen.contains($0.lowercased()) }
    }
}
