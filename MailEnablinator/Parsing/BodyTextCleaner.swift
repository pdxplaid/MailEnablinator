import Foundation

// Strips #tag, and trailing #tag patterns from an email body, producing the caption text.
enum BodyTextCleaner {
    nonisolated static func strip(_ body: String) -> String {
        var result = body
        // Remove comma-terminated tags: #tag,
        result = result.replacing(/#[^,#]+,/, with: "")
        // Remove any remaining #tag (end of string, no comma)
        result = result.replacing(/#[^#\n]+/, with: "")
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
