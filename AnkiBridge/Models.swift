import Foundation

// MARK: - Note kind toggle

/// The two note types the app can produce. Toggled at the top of the window.
enum NoteKind: String, CaseIterable, Identifiable, Codable {
    case basic = "Basic"
    case cloze = "Cloze"

    var id: String { rawValue }

    /// Anki model (note type) name this maps to.
    var ankiModelName: String { rawValue }
}

// MARK: - Chat

enum ChatRole: String, Codable {
    case system
    case user
    case assistant
}

struct ChatMessage: Identifiable, Codable, Equatable {
    var id = UUID()
    var role: ChatRole
    var text: String
    /// Reasoning / "thinking" output, shown in a collapsible box (assistant only).
    var reasoning: String = ""
    var attachments: [Attachment] = []
    /// The model that produced this message (assistant only); shown beneath the bubble.
    var model: String = ""
    var date = Date()
}

// MARK: - Cards

/// A flashcard produced during this session. Mirrors the fields shown in the
/// Anki editor so it can be edited before being pushed.
struct NoteCard: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: NoteKind

    // Basic fields.
    var front: String = ""
    var back: String = ""

    // Cloze field.
    var clozeText: String = ""

    /// Extra material. For Cloze this is the "Back Extra" field; for Basic it is
    /// appended to "Back". Attached images are embedded here on send.
    var extra: String = ""

    /// Images attached to the chat turn that produced this card. Embedded into the
    /// extra field via AnkiConnect's media support when the note is created.
    var imageAttachments: [Attachment] = []

    var deck: String = "Default"
    var tags: [String] = ["#AI"]

    /// True once this note has been accepted by AnkiConnect.
    var sentToAnki: Bool = false
    /// The note id returned by AnkiConnect, if sent.
    var ankiNoteID: Int64? = nil

    /// A short label for the list sidebar.
    var title: String {
        let raw: String
        switch kind {
        case .basic: raw = front
        case .cloze: raw = clozeText
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Untitled card" }
        let stripped = NoteCard.stripHTMLAndCloze(trimmed)
        return String(stripped.prefix(80))
    }

    static func stripHTMLAndCloze(_ s: String) -> String {
        var out = s
        // Strip simple HTML tags.
        out = out.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        // Reveal cloze answers for the title preview: {{c1::answer}} -> [answer]
        out = out.replacingOccurrences(
            of: "\\{\\{c\\d+::(.*?)(::.*?)?\\}\\}",
            with: "[$1]",
            options: .regularExpression
        )
        return out.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The field that "extra" material (and attached images) map onto for this
    /// note type. Cloze has a dedicated "Back Extra"; Basic has no extra field,
    /// so it folds into "Back".
    var extraFieldName: String {
        switch kind {
        case .basic: return "Back"
        case .cloze: return "Back Extra"
        }
    }

    /// Maps editable fields onto Anki field names for the chosen model.
    var ankiFields: [String: String] {
        switch kind {
        case .basic:
            var b = back
            if !extra.isEmpty {
                b += (b.isEmpty ? "" : "<br><br>") + extra
            }
            return ["Front": front, "Back": b]
        case .cloze:
            return ["Text": clozeText, "Back Extra": extra]
        }
    }
}

// MARK: - Decks

/// A node in the Anki deck tree. Anki decks are flat strings joined by "::";
/// this reconstructs the hierarchy for display in the sidebar.
final class DeckNode: Identifiable, ObservableObject {
    let id: String          // full deck name, e.g. "Languages::Spanish"
    let name: String        // leaf component, e.g. "Spanish"
    @Published var children: [DeckNode]

    init(id: String, name: String, children: [DeckNode] = []) {
        self.id = id
        self.name = name
        self.children = children
    }

    /// Builds a tree from a flat list of full deck names.
    static func buildTree(from deckNames: [String]) -> [DeckNode] {
        var roots: [DeckNode] = []
        var index: [String: DeckNode] = [:]

        for full in deckNames.sorted() {
            let parts = full.components(separatedBy: "::")
            var path = ""
            var currentParent: DeckNode? = nil

            for (i, part) in parts.enumerated() {
                path = i == 0 ? part : path + "::" + part
                if let existing = index[path] {
                    currentParent = existing
                    continue
                }
                let node = DeckNode(id: path, name: part)
                index[path] = node
                if let parent = currentParent {
                    parent.children.append(node)
                } else {
                    roots.append(node)
                }
                currentParent = node
            }
        }
        return roots
    }
}
