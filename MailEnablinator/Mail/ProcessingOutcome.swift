enum ProcessingOutcome {
    case reject
    case sendReply(String)
    case processImages([ProcessedImageInput], replyText: String?)

    enum ServerAction {
        case markSeenAndMove  // mark \Seen, move to ME-Processed
        case delete           // \Deleted + EXPUNGE
    }
}

struct ProcessedImageInput: Sendable {
    let attachment: MailAttachment
    let title: String
    let caption: String
    let keywords: [String]
    let finderTags: [String]
}
