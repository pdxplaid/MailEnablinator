import Foundation

// Pure decision logic — no networking, no I/O. Easily unit-testable.
enum MailProcessor {
    nonisolated static func process(
        message: MailMessage,
        allowedEmails: [String],
        defaultRmTag: DefaultRmTag,
        deleteAfterProcessing: Bool
    ) -> ProcessingOutcome {
        // Unknown sender → silently reject
        guard allowedEmails.contains(message.from.lowercased()) else {
            return .reject
        }

        let images = message.imageAttachments
        let nonImages = message.nonImageAttachments

        if images.isEmpty && nonImages.isEmpty {
            return .sendReply("no-image")
        }

        if images.isEmpty {
            return .sendReply("non-image")
        }

        // Build image inputs
        let tags = HashtagParser.parse(message.plainBody)
        let caption = BodyTextCleaner.strip(message.plainBody)
        let keywords = tags
        let hasRmTag = tags.contains(where: { $0.lowercased().hasPrefix("rm ") })
        let finderTags = hasRmTag ? keywords : keywords + [defaultRmTag.rawValue]

        let count = images.count
        let imageInputs = images.enumerated().map { idx, att -> ProcessedImageInput in
            let indexedCaption: String
            if count == 1 {
                indexedCaption = caption
            } else {
                let suffix = "(\(idx + 1) of \(count))"
                indexedCaption = caption.isEmpty ? suffix : "\(caption) \(suffix)"
            }
            return ProcessedImageInput(
                attachment: att,
                title: message.subject,
                caption: indexedCaption,
                keywords: keywords,
                finderTags: finderTags
            )
        }

        let replyText: String? = nonImages.isEmpty ? nil : "mixed"
        return .processImages(imageInputs, replyText: replyText)
    }
}
