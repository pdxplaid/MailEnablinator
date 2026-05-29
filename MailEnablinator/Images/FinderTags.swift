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

    // Returns the file's Finder tags, with any Finder color-index suffix (\nN) stripped.
    nonisolated static func read(at url: URL) -> [String] {
        let key = "com.apple.metadata:_kMDItemUserTags"
        let size = getxattr(url.path, key, nil, 0, 0, 0)
        guard size > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        let read = getxattr(url.path, key, &buffer, size, 0, 0)
        guard read == size else { return [] }
        let data = Data(buffer)
        guard
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
            let tags = plist as? [String]
        else { return [] }
        // Strip Finder color-index suffix "\nN" that Finder appends when a color is set.
        return tags.map { tag in
            tag.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? tag
        }
    }
}
