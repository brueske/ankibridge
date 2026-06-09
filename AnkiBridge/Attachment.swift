import Foundation
import PDFKit

enum AttachmentKind: String, Codable {
    case image
    case pdf
    case text
    case other
}

/// A file the user attached to a chat turn as context.
struct Attachment: Identifiable, Codable, Equatable {
    var id = UUID()
    var filename: String
    var kind: AttachmentKind
    var data: Data
    var mimeType: String
    /// Extracted text for pdf/text attachments; nil for images and unreadable files.
    var extractedText: String?

    /// Base64 data URL, used to send images to a vision-capable model.
    var dataURL: String {
        "data:\(mimeType);base64,\(data.base64EncodedString())"
    }

    var isImage: Bool { kind == .image }

    /// Loads and classifies a file from disk. Handles sandbox security scope.
    static func load(from url: URL) -> Attachment? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url) else { return nil }
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()

        let imageMIME: [String: String] = [
            "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
            "gif": "image/gif", "webp": "image/webp", "bmp": "image/bmp",
            "tiff": "image/tiff", "tif": "image/tiff", "heic": "image/heic",
        ]

        if let mime = imageMIME[ext] {
            return Attachment(filename: name, kind: .image, data: data, mimeType: mime, extractedText: nil)
        }
        if ext == "pdf" {
            let text = PDFDocument(data: data)?.string
            return Attachment(filename: name, kind: .pdf, data: data,
                              mimeType: "application/pdf", extractedText: text)
        }
        if let text = String(data: data, encoding: .utf8) {
            return Attachment(filename: name, kind: .text, data: data,
                              mimeType: "text/plain", extractedText: text)
        }
        return Attachment(filename: name, kind: .other, data: data,
                          mimeType: "application/octet-stream", extractedText: nil)
    }

    var symbolName: String {
        switch kind {
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .text: return "doc.text"
        case .other: return "doc"
        }
    }
}
