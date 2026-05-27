import SwiftUI
import UniformTypeIdentifiers

struct ExportableLog: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    let text: String

    init(entries: [ActivityLogEntry]) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        text = entries.map { entry in
            let tag: String = switch entry.level {
            case .info:    "INFO"
            case .success: "OK  "
            case .warning: "WARN"
            case .error:   "ERR "
            }
            return "[\(formatter.string(from: entry.date))] [\(tag)] \(entry.message)"
        }.joined(separator: "\n")
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: text.data(using: .utf8) ?? Data())
    }
}
