import Foundation

/// Extracts flashcards from an assistant message that may contain a fenced
/// ```anki JSON block, and returns the prose with that block removed.
enum CardParser {
    private struct ProtoCard: Decodable {
        let type: String
        let front: String?
        let back: String?
        let text: String?
        let extra: String?
    }

    /// Returns (visibleProse, cards).
    static func extract(from message: String) -> (String, [NoteCard]) {
        guard let (json, range) = firstAnkiBlock(in: message) else {
            return (message, [])
        }
        var prose = message
        prose.removeSubrange(range)

        let cards = parseCards(json)
        return (prose, cards)
    }

    /// Finds the JSON payload of the first ```anki fenced block and the range to strip.
    private static func firstAnkiBlock(in message: String) -> (String, Range<String.Index>)? {
        // Match ```anki ... ``` (allow optional whitespace/newline after the tag).
        let pattern = "```\\s*anki\\s*\\n([\\s\\S]*?)```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let ns = message as NSString
        guard let match = regex.firstMatch(in: message, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2,
              let full = Range(match.range, in: message),
              let group = Range(match.range(at: 1), in: message)
        else {
            // Fallback: a bare ```json or ``` block containing a JSON array.
            return bareJSONArray(in: message)
        }
        return (String(message[group]), full)
    }

    private static func bareJSONArray(in message: String) -> (String, Range<String.Index>)? {
        let pattern = "```(?:json)?\\s*\\n(\\[[\\s\\S]*?\\])\\s*```"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let ns = message as NSString
        guard let match = regex.firstMatch(in: message, range: NSRange(location: 0, length: ns.length)),
              match.numberOfRanges >= 2,
              let full = Range(match.range, in: message),
              let group = Range(match.range(at: 1), in: message)
        else { return nil }
        return (String(message[group]), full)
    }

    private static func parseCards(_ json: String) -> [NoteCard] {
        guard let data = json.data(using: .utf8) else { return [] }
        guard let protos = try? JSONDecoder().decode([ProtoCard].self, from: data) else { return [] }
        return protos.compactMap { proto in
            switch proto.type.lowercased() {
            case "cloze":
                let text = proto.text ?? proto.front ?? ""
                guard !text.isEmpty else { return nil }
                var c = NoteCard(kind: .cloze)
                c.clozeText = text
                c.extra = proto.extra ?? proto.back ?? ""
                return c
            default: // "basic"
                let front = proto.front ?? proto.text ?? ""
                let back = proto.back ?? ""
                guard !front.isEmpty || !back.isEmpty else { return nil }
                var c = NoteCard(kind: .basic)
                c.front = front
                c.back = back
                c.extra = proto.extra ?? ""
                return c
            }
        }
    }
}
