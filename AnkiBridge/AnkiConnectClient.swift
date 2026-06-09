import Foundation

enum AnkiError: LocalizedError {
    case badURL
    case transport(String)
    case api(String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "The AnkiConnect URL is invalid."
        case .transport(let m): return "Could not reach AnkiConnect: \(m). Is Anki running with the AnkiConnect add-on?"
        case .api(let m): return "AnkiConnect error: \(m)"
        case .decoding(let m): return "Could not decode the AnkiConnect response: \(m)"
        }
    }
}

/// Client for the AnkiConnect add-on (https://foosoft.net/projects/anki-connect/).
struct AnkiConnectClient {
    var urlString: String

    private struct Envelope<P: Encodable>: Encodable {
        let action: String
        let version: Int = 6
        let params: P
    }

    private struct Empty: Encodable {}

    /// AnkiConnect always returns {result, error}. error is null on success.
    private struct Reply<R: Decodable>: Decodable {
        let result: R?
        let error: String?
    }

    private func send<P: Encodable, R: Decodable>(action: String, params: P, as: R.Type) async throws -> R {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)) else {
            throw AnkiError.badURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        req.httpBody = try JSONEncoder().encode(Envelope(action: action, params: params))

        let data: Data
        do {
            let (d, _) = try await URLSession.shared.data(for: req)
            data = d
        } catch {
            throw AnkiError.transport(error.localizedDescription)
        }

        do {
            let reply = try JSONDecoder().decode(Reply<R>.self, from: data)
            if let err = reply.error, !err.isEmpty { throw AnkiError.api(err) }
            guard let result = reply.result else {
                // Some actions legitimately return null (e.g. createDeck on dupes); caller handles.
                throw AnkiError.api("Empty result for action \(action).")
            }
            return result
        } catch let e as AnkiError {
            throw e
        } catch {
            throw AnkiError.decoding(error.localizedDescription)
        }
    }

    /// For actions whose successful result is null (e.g. updateNoteFields).
    /// Only the `error` field is inspected.
    private struct ErrorOnly: Decodable { let error: String? }

    private func sendNoResult<P: Encodable>(action: String, params: P) async throws {
        guard let url = URL(string: urlString.trimmingCharacters(in: .whitespaces)) else {
            throw AnkiError.badURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        req.httpBody = try JSONEncoder().encode(Envelope(action: action, params: params))

        let data: Data
        do {
            let (d, _) = try await URLSession.shared.data(for: req)
            data = d
        } catch {
            throw AnkiError.transport(error.localizedDescription)
        }
        do {
            let reply = try JSONDecoder().decode(ErrorOnly.self, from: data)
            if let err = reply.error, !err.isEmpty { throw AnkiError.api(err) }
        } catch let e as AnkiError {
            throw e
        } catch {
            throw AnkiError.decoding(error.localizedDescription)
        }
    }

    // MARK: - Actions

    /// Returns the AnkiConnect API version; used as a connectivity ping.
    func version() async throws -> Int {
        try await send(action: "version", params: Empty(), as: Int.self)
    }

    /// All deck names (flat, "::"-joined).
    func deckNames() async throws -> [String] {
        try await send(action: "deckNames", params: Empty(), as: [String].self)
    }

    /// Creates a deck (and any missing parents). Idempotent on the Anki side.
    @discardableResult
    func createDeck(_ name: String) async throws -> Int64 {
        struct P: Encodable { let deck: String }
        return try await send(action: "createDeck", params: P(deck: name), as: Int64.self)
    }

    private struct Picture: Encodable {
        let data: String        // base64-encoded image bytes
        let filename: String
        let fields: [String]    // fields to embed the <img> into
    }

    private struct NotePayload: Encodable {
        struct Options: Encodable {
            let allowDuplicate: Bool
            let duplicateScope: String
        }
        let deckName: String
        let modelName: String
        let fields: [String: String]
        let tags: [String]
        let options: Options
        let picture: [Picture]?
    }

    /// Adds a single note, returning the created note id. Any image attachments on
    /// the card are uploaded and embedded into its extra field.
    func addNote(_ card: NoteCard, allowDuplicate: Bool = false) async throws -> Int64 {
        struct P: Encodable { let note: NotePayload }
        let pictures: [Picture]? = card.imageAttachments.isEmpty ? nil : card.imageAttachments.map {
            Picture(
                data: $0.data.base64EncodedString(),
                filename: "ankibridge-\($0.id.uuidString).\(Self.fileExtension(for: $0.mimeType))",
                fields: [card.extraFieldName]
            )
        }
        let note = NotePayload(
            deckName: card.deck,
            modelName: card.kind.ankiModelName,
            fields: card.ankiFields,
            tags: card.tags,
            options: .init(allowDuplicate: allowDuplicate, duplicateScope: "deck"),
            picture: pictures
        )
        return try await send(action: "addNote", params: P(note: note), as: Int64.self)
    }

    private static func fileExtension(for mime: String) -> String {
        switch mime {
        case "image/png": return "png"
        case "image/jpeg": return "jpg"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "image/bmp": return "bmp"
        case "image/tiff": return "tiff"
        case "image/heic": return "heic"
        default: return "png"
        }
    }

    /// Updates the fields of an existing note (identified by its note id).
    /// Note: AnkiConnect's updateNoteFields changes fields only, not deck or tags.
    func updateNoteFields(id: Int64, fields: [String: String]) async throws {
        struct NoteUpdate: Encodable {
            let id: Int64
            let fields: [String: String]
        }
        struct P: Encodable { let note: NoteUpdate }
        try await sendNoResult(action: "updateNoteFields", params: P(note: NoteUpdate(id: id, fields: fields)))
    }
}
