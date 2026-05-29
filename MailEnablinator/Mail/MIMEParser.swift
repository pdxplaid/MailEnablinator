import Foundation
import os

// Parses RFC 2822 / MIME email messages into MailMessage.
// Handles: multipart/mixed, multipart/alternative, multipart/related,
// text/plain, text/html (HTML → plain text fallback), image/*,
// base64 and quoted-printable transfer encodings, RFC 2047 encoded-word headers.
nonisolated enum MIMEParser {
    enum MIMEError: Error { case invalidMessage }

    private static let logger = Logger(subsystem: "com.plaidapps.MailEnablinator", category: "MIMEParser")

    // Returns the parsed message plus a one-line debug summary for the activity log.
    static func parse(_ data: Data, uid: UInt32) -> (message: MailMessage, debugInfo: String) {
        let decoded = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        // Normalize to LF-only throughout. CharacterSet.newlines splits \r and \n as two
        // separate characters, which inserts phantom blank lines into reassembled multipart
        // parts and causes splitHeadersAndBody to split mid-header on folded header lines.
        let raw = decoded.replacing("\r\n", with: "\n")
        let (headerBlock, bodyBlock) = splitHeadersAndBody(raw)
        let headers = parseHeaders(headerBlock)
        let contentType = headers["content-type"] ?? "text/plain"
        let from = decodeRFC2047(headers["from"] ?? "")
        let subject = decodeRFC2047(headers["subject"] ?? "")
        let messageID = headers["message-id"]
        let date = parseDate(headers["date"] ?? "")

        var plainBody = ""
        var htmlBody = ""
        var attachments: [MailAttachment] = []
        parseBody(
            body: bodyBlock,
            contentType: contentType,
            headers: headers,
            plainBody: &plainBody,
            htmlBody: &htmlBody,
            attachments: &attachments
        )

        // iOS Mail often sends only text/html (no text/plain) when the email contains
        // an inline image. Use the HTML part as a plain-text fallback so body text and
        // hashtags (e.g. #Rm2H) are not silently discarded.
        let htmlFallbackFired: Bool
        if plainBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !htmlBody.isEmpty {
            plainBody = htmlToPlainText(htmlBody)
            htmlFallbackFired = true
        } else {
            htmlFallbackFired = false
        }

        let tree = mimeTree(body: bodyBlock, contentType: contentType, depth: 0)
        let debugInfo = "ct=\(contentType.prefix(80)) raw=\(data.count)B plain=\(plainBody.count)ch html=\(htmlBody.count)ch htmlFallback=\(htmlFallbackFired)\nMIME tree:\n\(tree)"
        logger.debug("uid=\(uid) \(debugInfo)")

        let message = MailMessage(
            uid: uid,
            from: extractEmail(from),
            subject: subject,
            plainBody: plainBody.trimmingCharacters(in: .whitespacesAndNewlines),
            attachments: attachments,
            messageID: messageID,
            date: date
        )
        return (message, debugInfo)
    }

    // MARK: - MIME tree (diagnostic only)

    private static func mimeTree(body: String, contentType: String, depth: Int) -> String {
        let indent = String(repeating: "  ", count: depth)
        let ctShort = contentType.prefix(80)
        var out = "\(indent)[\(ctShort)]\n"
        let ct = contentType.lowercased()
        guard ct.hasPrefix("multipart/") else { return out }
        guard let boundary = extractParameter("boundary", from: contentType) else {
            return out + "\(indent)  (no boundary extracted)\n"
        }
        let parts = splitMultipart(body, boundary: boundary)
        if parts.isEmpty {
            out += "\(indent)  (0 parts found for boundary=\(boundary.prefix(40)))\n"
        }
        for (i, part) in parts.enumerated() {
            let (ph, pb) = splitHeadersAndBody(part)
            let parsedHeaders = parseHeaders(ph)
            let partCT = parsedHeaders["content-type"] ?? "(no content-type)"
            let partDisp = parsedHeaders["content-disposition"] ?? ""
            let dispNote = partDisp.isEmpty ? "" : " disp=\(partDisp.prefix(30))"
            out += "\(indent)  Part \(i + 1): \(partCT.prefix(70))\(dispNote)\n"
            if partCT.lowercased().hasPrefix("multipart/") {
                out += mimeTree(body: pb, contentType: partCT, depth: depth + 2)
            }
        }
        return out
    }

    // MARK: - Body dispatch

    private static func parseBody(
        body: String,
        contentType: String,
        headers: [String: String],
        plainBody: inout String,
        htmlBody: inout String,
        attachments: inout [MailAttachment]
    ) {
        let ct = contentType.lowercased()
        if ct.hasPrefix("multipart/") {
            guard let boundary = extractParameter("boundary", from: contentType) else { return }
            let parts = splitMultipart(body, boundary: boundary)
            for part in parts {
                let (partHeaders, partBody) = splitHeadersAndBody(part)
                let parsedHeaders = parseHeaders(partHeaders)
                let partCT = parsedHeaders["content-type"] ?? "text/plain"
                let disposition = parsedHeaders["content-disposition"] ?? ""
                let partCTLower = partCT.lowercased()
                if partCTLower.hasPrefix("multipart/") {
                    parseBody(body: partBody, contentType: partCT, headers: parsedHeaders,
                              plainBody: &plainBody, htmlBody: &htmlBody, attachments: &attachments)
                } else if partCTLower.hasPrefix("text/plain") && !disposition.lowercased().contains("attachment") {
                    let dec = decodeTransferEncoding(partBody, encoding: parsedHeaders["content-transfer-encoding"] ?? "7bit")
                    // Concatenate all text/plain parts. iOS Mail splits body text before and after
                    // an inline image into separate text/plain parts; taking only the first silently
                    // drops the user's text (and any hashtag tags) that appear after the image.
                    plainBody += plainBody.isEmpty ? dec : "\n\(dec)"
                } else if partCTLower.hasPrefix("text/html") && !disposition.lowercased().contains("attachment") {
                    let dec = decodeTransferEncoding(partBody, encoding: parsedHeaders["content-transfer-encoding"] ?? "7bit")
                    if htmlBody.isEmpty { htmlBody = dec }
                } else if partCTLower.hasPrefix("image/") || disposition.lowercased().contains("attachment") {
                    if let att = buildAttachment(headers: parsedHeaders, body: partBody, fallbackCT: partCT) {
                        attachments.append(att)
                    }
                }
            }
        } else if ct.hasPrefix("text/plain") {
            let encoding = headers["content-transfer-encoding"] ?? "7bit"
            plainBody = decodeTransferEncoding(body, encoding: encoding)
        } else if ct.hasPrefix("text/html") {
            let encoding = headers["content-transfer-encoding"] ?? "7bit"
            htmlBody = decodeTransferEncoding(body, encoding: encoding)
        } else if ct.hasPrefix("image/") {
            if let att = buildAttachment(headers: headers, body: body, fallbackCT: contentType) {
                attachments.append(att)
            }
        }
    }

    // MARK: - HTML → plain text

    // Strips HTML tags and decodes common entities so the resulting plain text
    // can be parsed for hashtags and used as an IPTC caption.
    private static func htmlToPlainText(_ html: String) -> String {
        var text = html
        // Strip all HTML tags (including attributes).
        text = text.replacing(/<[^>]*>/, with: " ")
        // Decode the handful of HTML entities that appear in typical Apple Mail bodies.
        text = text
            .replacing("&amp;",  with: "&")
            .replacing("&lt;",   with: "<")
            .replacing("&gt;",   with: ">")
            .replacing("&quot;", with: "\"")
            .replacing("&#39;",  with: "'")
            .replacing("&apos;", with: "'")
            .replacing("&nbsp;", with: " ")
        // Collapse all runs of whitespace to a single space.
        text = text.replacing(/\s+/, with: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Part construction

    private static func buildAttachment(headers: [String: String], body: String, fallbackCT: String) -> MailAttachment? {
        let cte = headers["content-transfer-encoding"] ?? "7bit"
        let ct = (headers["content-type"] ?? fallbackCT)
            .components(separatedBy: ";").first?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? fallbackCT
        let filename = extractFilename(from: headers)
        guard let data = decodeTransferEncodingToData(body, encoding: cte), !data.isEmpty else { return nil }
        return MailAttachment(filename: filename, data: data, contentType: ct)
    }

    // MARK: - Header parsing

    private static func splitHeadersAndBody(_ message: String) -> (String, String) {
        let doubleCRLF = "\r\n\r\n"
        let doubleLF = "\n\n"
        if let range = message.range(of: doubleCRLF) {
            return (String(message[..<range.lowerBound]), String(message[range.upperBound...]))
        }
        if let range = message.range(of: doubleLF) {
            return (String(message[..<range.lowerBound]), String(message[range.upperBound...]))
        }
        return (message, "")
    }

    private static func parseHeaders(_ block: String) -> [String: String] {
        let unfolded = block
            .replacing(/\r\n[ \t]+/, with: " ")
            .replacing(/\n[ \t]+/, with: " ")
        var result: [String: String] = [:]
        let lines = unfolded.components(separatedBy: CharacterSet.newlines)
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            result[key] = value
        }
        return result
    }

    // MARK: - Multipart splitting

    private static func splitMultipart(_ body: String, boundary: String) -> [String] {
        let delimiter = "--\(boundary)"
        let terminator = "--\(boundary)--"
        var parts: [String] = []
        var current = ""
        var inside = false
        let lines = body.components(separatedBy: CharacterSet.newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == terminator { break }
            if trimmed == delimiter {
                if inside && !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    parts.append(current)
                }
                current = ""
                inside = true
            } else if inside {
                current += line + "\n"
            }
        }
        if inside && !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(current)
        }
        return parts
    }

    // MARK: - Transfer encoding

    private static func decodeTransferEncoding(_ body: String, encoding: String) -> String {
        switch encoding.lowercased().trimmingCharacters(in: .whitespaces) {
        case "base64":
            let cleaned = body.replacing(/\s+/, with: "")
            guard let data = Data(base64Encoded: cleaned),
                  let str = String(data: data, encoding: .utf8) else { return body }
            return str
        case "quoted-printable":
            return decodeQuotedPrintable(body)
        default:
            return body
        }
    }

    private static func decodeTransferEncodingToData(_ body: String, encoding: String) -> Data? {
        switch encoding.lowercased().trimmingCharacters(in: .whitespaces) {
        case "base64":
            let cleaned = body.replacing(/\s+/, with: "")
            return Data(base64Encoded: cleaned)
        case "quoted-printable":
            let str = decodeQuotedPrintable(body)
            return str.data(using: .utf8)
        default:
            return body.data(using: .utf8)
        }
    }

    private static func decodeQuotedPrintable(_ input: String) -> String {
        var result = ""
        var idx = input.startIndex
        while idx < input.endIndex {
            let char = input[idx]
            if char == "=" {
                let next = input.index(after: idx)
                if next == input.endIndex { break }
                let afterNext = input.index(after: next)
                if afterNext == input.endIndex { result.append(char); idx = next; continue }
                let hexStr = String(input[next...afterNext])
                if hexStr == "\r\n" || hexStr.hasPrefix("\n") {
                    // Soft line break — skip
                } else if let code = UInt8(hexStr, radix: 16) {
                    result.append(Character(UnicodeScalar(code)))
                } else {
                    result.append(char)
                    idx = next
                    continue
                }
                idx = input.index(after: afterNext)
            } else {
                result.append(char)
                idx = input.index(after: idx)
            }
        }
        return result
    }

    // MARK: - RFC 2047 encoded-word decoding

    private static func decodeRFC2047(_ input: String) -> String {
        var result = input
        let pattern = /=\?([^?]+)\?([BbQq])\?([^?]*)\?=/
        var searchFrom = result.startIndex
        while let match = result[searchFrom...].firstMatch(of: pattern) {
            let charset = String(match.output.1)
            let enc = String(match.output.2).uppercased()
            let text = String(match.output.3)
            var decoded = text
            if enc == "B" {
                if let data = Data(base64Encoded: text), let str = decodeData(data, ianaCharset: charset) {
                    decoded = str
                }
            } else if enc == "Q" {
                decoded = decodeQuotedPrintable(text.replacing("_", with: " "))
            }
            let matchRange = match.range
            result.replaceSubrange(matchRange, with: decoded)
            let offset = result.distance(from: result.startIndex, to: matchRange.lowerBound) + decoded.count
            searchFrom = result.index(result.startIndex, offsetBy: min(offset, result.count))
        }
        return result
    }

    private static func decodeData(_ data: Data, ianaCharset: String) -> String? {
        let cfEnc = CFStringConvertIANACharSetNameToEncoding(ianaCharset as CFString)
        guard cfEnc != kCFStringEncodingInvalidId else { return String(data: data, encoding: .utf8) }
        return String(data: data, encoding: .init(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEnc)))
    }

    // MARK: - Helpers

    private static func extractEmail(_ header: String) -> String {
        if let ltRange = header.range(of: "<"), let gtRange = header.range(of: ">"),
           ltRange.upperBound < gtRange.lowerBound {
            return String(header[ltRange.upperBound..<gtRange.lowerBound]).lowercased()
        }
        return header.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractParameter(_ param: String, from header: String) -> String? {
        let lowered = header.lowercased()
        let search = "\(param)="
        guard let range = lowered.range(of: search) else { return nil }
        let afterEq = header[range.upperBound...]
        if afterEq.hasPrefix("\"") {
            let inner = afterEq.dropFirst()
            if let endQuote = inner.firstIndex(of: "\"") {
                return String(inner[..<endQuote])
            }
        }
        let end = afterEq.firstIndex(where: { $0 == ";" || $0 == "\r" || $0 == "\n" }) ?? afterEq.endIndex
        return String(afterEq[..<end]).trimmingCharacters(in: .whitespaces)
    }

    private static func extractFilename(from headers: [String: String]) -> String {
        if let disp = headers["content-disposition"],
           let name = extractParameter("filename", from: disp) {
            return name
        }
        if let ct = headers["content-type"],
           let name = extractParameter("name", from: ct) {
            return name
        }
        return "attachment"
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "dd MMM yyyy HH:mm:ss Z",
            "EEE, dd MMM yyyy HH:mm:ss zzz"
        ]
        for fmt in formats {
            formatter.dateFormat = fmt
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}
