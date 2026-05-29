import Foundation

enum ArchiveMover {
    // Moves source into archiveRoot (optionally into a YYYY-MM-DD subfolder based on addedDate).
    // Security scope for both URLs must be held by the caller before calling this.
    @discardableResult
    nonisolated static func move(
        _ source: URL,
        to archiveRoot: URL,
        addedDate: Date,
        useDateSubfolder: Bool
    ) throws -> URL {
        let targetFolder: URL
        if useDateSubfolder {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd"
            df.calendar = Calendar.current
            df.locale = Locale(identifier: "en_US_POSIX")
            let folderName = df.string(from: addedDate)
            targetFolder = archiveRoot.appending(path: folderName)
            try FileManager.default.createDirectory(at: targetFolder, withIntermediateDirectories: true)
        } else {
            targetFolder = archiveRoot
        }

        let finalURL = DestinationFile.uniqueURL(in: targetFolder, for: source.lastPathComponent)

        var moveError: Error?
        var coordError: NSError?
        NSFileCoordinator().coordinate(
            writingItemAt: source, options: .forMoving,
            writingItemAt: finalURL, options: .forReplacing,
            error: &coordError
        ) { src, dst in
            do {
                try FileManager.default.moveItem(at: src, to: dst)
            } catch {
                moveError = error
            }
        }
        if let err = coordError { throw err }
        if let err = moveError  { throw err }
        return finalURL
    }
}
