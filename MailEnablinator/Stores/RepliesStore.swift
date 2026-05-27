import Foundation
import Observation

@MainActor
@Observable
final class RepliesStore {
    private enum Keys {
        static let noImage = "replyNoImage"
        static let nonImage = "replyNonImage"
        static let mixed = "replyMixed"
    }

    static let defaultNoImage = "Thanks for the message — but it looks like no image was attached. Please resend with an image attachment."
    static let defaultNonImage = "This address only accepts image attachments. Your attachment couldn't be processed."
    static let defaultMixed = "Your image has been processed. Note that any non-image attachments in your message were ignored."

    var noImageReply: String {
        get { UserDefaults.standard.string(forKey: Keys.noImage) ?? Self.defaultNoImage }
        set { UserDefaults.standard.set(newValue, forKey: Keys.noImage) }
    }

    var nonImageReply: String {
        get { UserDefaults.standard.string(forKey: Keys.nonImage) ?? Self.defaultNonImage }
        set { UserDefaults.standard.set(newValue, forKey: Keys.nonImage) }
    }

    var mixedReply: String {
        get { UserDefaults.standard.string(forKey: Keys.mixed) ?? Self.defaultMixed }
        set { UserDefaults.standard.set(newValue, forKey: Keys.mixed) }
    }
}
