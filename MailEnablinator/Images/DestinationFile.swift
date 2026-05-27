import Foundation

enum DestinationFile {
    nonisolated static func uniqueURL(in folder: URL, for filename: String) -> URL {
        let name = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var candidate = folder.appending(path: filename)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path()) {
            let disambiguated = ext.isEmpty ? "\(name) (\(counter))" : "\(name) (\(counter)).\(ext)"
            candidate = folder.appending(path: disambiguated)
            counter += 1
        }
        return candidate
    }

    nonisolated static func exportFilename(title: String, originalFilename: String) -> String {
        let slug = camelCaseSlug(from: title)
        return slug.isEmpty ? originalFilename : "\(slug)-\(originalFilename)"
    }

    nonisolated private static func camelCaseSlug(from string: String) -> String {
        let words = string.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return "" }
        let first = words[0].lowercased()
        let rest = words.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
        return ([first] + rest).joined()
    }
}
