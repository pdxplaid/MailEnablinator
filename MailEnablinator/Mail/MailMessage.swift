import Foundation

struct MailMessage: Sendable {
    let uid: UInt32
    let from: String
    let subject: String
    let plainBody: String
    let attachments: [MailAttachment]
    let messageID: String?
    let date: Date?

    nonisolated var imageAttachments: [MailAttachment] { attachments.filter(\.isSupportedImageFormat) }
    nonisolated var nonImageAttachments: [MailAttachment] { attachments.filter { !$0.isImage } }
    nonisolated var unsupportedImageAttachments: [MailAttachment] { attachments.filter { $0.isImage && !$0.isSupportedImageFormat } }
}
