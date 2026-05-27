import Foundation

// Writes IPTC metadata and Finder tags to an image, then copies it into the destination folder.
// All file operations run on a detached task; call from a background context.
enum ImageImporter {
    struct Input: Sendable {
        let imageData: Data
        let filename: String
        let title: String
        let caption: String
        let keywords: [String]
        let finderTags: [String]
        let destinationFolder: URL
    }

    nonisolated static func importImage(_ input: Input) throws {
        let tempDir = FileManager.default.temporaryDirectory
        let srcURL = tempDir.appending(path: "\(UUID().uuidString)-\(input.filename)")
        let outputURL = tempDir.appending(path: "\(UUID().uuidString)-\(input.filename)")

        try input.imageData.write(to: srcURL)
        defer { try? FileManager.default.removeItem(at: srcURL) }
        defer { try? FileManager.default.removeItem(at: outputURL) }

        try ImageMetadataWriter.embed(
            title: input.title,
            caption: input.caption,
            keywords: input.keywords,
            sourceURL: srcURL,
            outputURL: outputURL
        )

        let exportName = DestinationFile.exportFilename(title: input.title, originalFilename: input.filename)
        let finalURL = DestinationFile.uniqueURL(in: input.destinationFolder, for: exportName)

        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(writingItemAt: finalURL, options: .forReplacing, error: &coordinatorError) { writeURL in
            try? FileManager.default.copyItem(at: outputURL, to: writeURL)
            FinderTags.apply(input.finderTags, to: writeURL)
        }
        if let err = coordinatorError { throw err }
    }
}
