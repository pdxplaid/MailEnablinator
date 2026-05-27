import Foundation

// Parses #Tags from email body text.
// Format: single-word (#vacation) or multi-word (#Rm 1D,) terminated by comma.
// The # prefix and trailing comma are stripped from the returned strings.
enum HashtagParser {
    nonisolated static func parse(_ body: String) -> [String] {
        var tags: [String] = []
        let scanner = Scanner(string: body)
        scanner.charactersToBeSkipped = nil
        while !scanner.isAtEnd {
            _ = scanner.scanUpToString("#")
            guard !scanner.isAtEnd, scanner.scanString("#") != nil else { break }
            if let content = scanner.scanUpToString(",") {
                let tag = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !tag.isEmpty { tags.append(tag) }
                _ = scanner.scanString(",")
            } else {
                let rest = String(body[scanner.currentIndex...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !rest.isEmpty { tags.append(rest) }
                break
            }
        }
        return tags
    }
}
