import Foundation
import Observation

@MainActor
@Observable
final class DestinationStore {
    private enum Keys {
        static let bookmark             = "destinationBookmark"
        static let displayName          = "destinationDisplayName"
        static let destinationPath      = "destinationPath"
        static let defaultRmTag         = "destinationDefaultRmTag"
        static let archiveBookmark      = "archiveBookmark"
        static let archivePath          = "archivePath"
        static let archiveUseDateSubfolders = "archiveUseDateSubfolders"
        static let cullInterval         = "cullInterval"
    }

    // MARK: - Destination

    var displayName: String? {
        UserDefaults.standard.string(forKey: Keys.displayName)
    }

    var destinationPath: String? {
        UserDefaults.standard.string(forKey: Keys.destinationPath)
    }

    var defaultRmTag: DefaultRmTag {
        get {
            let raw = UserDefaults.standard.string(forKey: Keys.defaultRmTag)
                ?? DefaultRmTag.rm1D.rawValue
            // Migrate legacy spaced values ("Rm 1D" → "Rm1D") on first read.
            let normalized = raw.replacing(" ", with: "")
            if normalized != raw {
                UserDefaults.standard.set(normalized, forKey: Keys.defaultRmTag)
            }
            return DefaultRmTag(rawValue: normalized) ?? .rm1D
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
            UserDefaults.standard.set(Self.tildePath(for: url), forKey: Keys.destinationPath)
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

    // MARK: - Archive

    var archivePath: String? {
        UserDefaults.standard.string(forKey: Keys.archivePath)
    }

    var archiveUseDateSubfolders: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.archiveUseDateSubfolders) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.archiveUseDateSubfolders) }
    }

    func saveArchive(url: URL) {
        do {
            let data = try url.bookmarkData(options: .withSecurityScope)
            UserDefaults.standard.set(data, forKey: Keys.archiveBookmark)
            UserDefaults.standard.set(Self.tildePath(for: url), forKey: Keys.archivePath)
        } catch {
            // Bookmark creation failed — archive not saved.
        }
    }

    func resolveArchive() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: Keys.archiveBookmark) else { return nil }
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale { saveArchive(url: url) }
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Cull schedule

    var cullInterval: CullInterval {
        get {
            let raw = UserDefaults.standard.string(forKey: Keys.cullInterval) ?? CullInterval.hour.rawValue
            return CullInterval(rawValue: raw) ?? .hour
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Keys.cullInterval)
        }
    }

    // MARK: - Helpers

    private static func tildePath(for url: URL) -> String {
        (url.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
    }
}
