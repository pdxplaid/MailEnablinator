import Foundation
import Observation

@MainActor
@Observable
final class DestinationStore {
    private enum Keys {
        static let bookmark = "destinationBookmark"
        static let displayName = "destinationDisplayName"
        static let defaultRmTag = "destinationDefaultRmTag"
    }

    var displayName: String? {
        UserDefaults.standard.string(forKey: Keys.displayName)
    }

    var defaultRmTag: DefaultRmTag {
        get {
            let raw = UserDefaults.standard.string(forKey: Keys.defaultRmTag) ?? DefaultRmTag.rm1D.rawValue
            return DefaultRmTag(rawValue: raw) ?? .rm1D
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Keys.defaultRmTag)
        }
    }

    func saveDestination(url: URL) {
        do {
            let data = try url.bookmarkData(options: .withSecurityScope)
            UserDefaults.standard.set(data, forKey: Keys.bookmark)
            UserDefaults.standard.set(url.lastPathComponent, forKey: Keys.displayName)
        } catch {
            // Bookmark creation failed — destination not saved.
        }
    }

    func resolveDestination() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: Keys.bookmark) else { return nil }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale { saveDestination(url: url) }
            return url
        } catch {
            return nil
        }
    }
}
