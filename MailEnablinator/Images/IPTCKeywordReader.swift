import Foundation
import ImageIO

enum IPTCKeywordReader {
    // Returns IPTC Keywords embedded in the image at url, or [] for non-images / missing IPTC.
    nonisolated static func keywords(at url: URL) -> [String] {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let iptc = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any],
            let keywords = iptc[kCGImagePropertyIPTCKeywords] as? [String]
        else { return [] }
        return keywords
    }
}
