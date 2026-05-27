import Foundation
import UniformTypeIdentifiers

struct MailAttachment: Sendable {
    let filename: String
    let data: Data
    let contentType: String

    nonisolated var isImage: Bool {
        contentType.hasPrefix("image/")
    }

    // Returns true if ImageIO can write this format (our supported set)
    nonisolated var isSupportedImageFormat: Bool {
        let supported: Set<String> = ["image/jpeg", "image/png", "image/heic", "image/heif", "image/tiff"]
        return supported.contains(contentType.lowercased())
    }
}
