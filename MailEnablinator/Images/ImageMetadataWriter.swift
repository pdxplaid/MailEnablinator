import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageMetadataWriter {
    enum WriterError: Error, LocalizedError {
        case sourceCreationFailed
        case destinationCreationFailed
        case finalizationFailed

        var errorDescription: String? {
            switch self {
            case .sourceCreationFailed: "Could not read the image."
            case .destinationCreationFailed: "Could not prepare the output file."
            case .finalizationFailed: "Could not write metadata to the image."
            }
        }
    }

    // Embeds IPTC title, caption, and keywords into the image at sourceURL without re-encoding.
    // The original encoded image data is copied verbatim; only the metadata container
    // is rewritten, preserving quality and all existing EXIF/GPS fields.
    nonisolated static func embed(
        title: String,
        caption: String,
        keywords: [String] = [],
        sourceURL: URL,
        outputURL: URL
    ) throws {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil) else {
            throw WriterError.sourceCreationFailed
        }
        guard let uti = CGImageSourceGetType(source) else {
            throw WriterError.sourceCreationFailed
        }

        // Preserve any existing IPTC fields so we don't clobber them.
        var existingIPTC: [CFString: Any] = [:]
        if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let iptc = props[kCGImagePropertyIPTCDictionary] as? [CFString: Any] {
            existingIPTC = iptc
        }

        var mergedIPTC = existingIPTC
        mergedIPTC[kCGImagePropertyIPTCObjectName] = title
        mergedIPTC[kCGImagePropertyIPTCCaptionAbstract] = caption

        if !keywords.isEmpty {
            let existing = existingIPTC[kCGImagePropertyIPTCKeywords] as? [String] ?? []
            mergedIPTC[kCGImagePropertyIPTCKeywords] = existing + keywords
        }

        let metadata: [CFString: Any] = [kCGImagePropertyIPTCDictionary: mergedIPTC]

        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, uti, 1, nil) else {
            throw WriterError.destinationCreationFailed
        }

        // AddImageFromSource copies the original encoded stream verbatim — no re-encode.
        CGImageDestinationAddImageFromSource(destination, source, 0, metadata as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw WriterError.finalizationFailed
        }
    }
}
