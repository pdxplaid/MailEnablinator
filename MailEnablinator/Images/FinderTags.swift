import Foundation

enum FinderTags {
    nonisolated static func apply(_ tags: [String], to url: URL) {
        guard !tags.isEmpty,
              let plist = try? PropertyListSerialization.data(
                fromPropertyList: tags, format: .binary, options: 0
              ) else { return }
        plist.withUnsafeBytes { ptr in
            _ = setxattr(url.path, "com.apple.metadata:_kMDItemUserTags",
                         ptr.baseAddress, ptr.count, 0, 0)
        }
    }
}
