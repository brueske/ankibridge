import Foundation
import Combine
import AppKit

@MainActor
final class AppState: ObservableObject {
    let settings: AppSettings

    // Sidebar: models
    @Published var availableModels: [String] = []
    @Published var isLoadingModels = false

    // Sidebar: decks
    @Published var deckTree: [DeckNode] = []
    @Published var selectedDeck: String = "Default"
    @Published var isLoadingDecks = false

    // Top toggle
    @Published var noteKind: NoteKind = .basic

    // Chat
    @Published var messages: [ChatMessage] = []
    @Published var draft: String = ""
    @Published var isSending = false
    /// Files staged on the current draft, attached when the message is sent.
    @Published var pendingAttachments: [Attachment] = []

    // Cards produced this session
    @Published var cards: [NoteCard] = []
    /// Native multi-selection: drives both the editor (when exactly one is selected)
    /// and which cards the "Send to Anki" button / context menu act on.
    @Published var selection: Set<NoteCard.ID> = []
    @Published var isSendingToAnki = false

    // Status / errors
    @Published var statusMessage: String = ""
    @Published var errorMessage: String? = nil

    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
    }

    private var openAI: OpenAIClient {
        OpenAIClient(baseURL: settings.serverBaseURL, apiKey: settings.apiKey)
    }
    private var anki: AnkiConnectClient {
        AnkiConnectClient(urlString: settings.ankiConnectURL)
    }

    // MARK: - Models

    func refreshModels() async {
        isLoadingModels = true
        defer { isLoadingModels = false }
        do {
            let models = try await openAI.listModels()
            availableModels = models
            if settings.selectedModel.isEmpty || !models.contains(settings.selectedModel) {
                settings.selectedModel = models.first ?? ""
            }
            statusMessage = "Loaded \(models.count) model(s)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Decks

    func refreshDecks() async {
        isLoadingDecks = true
        defer { isLoadingDecks = false }
        do {
            let names = try await anki.deckNames()
            deckTree = DeckNode.buildTree(from: names)
            if !names.contains(selectedDeck) {
                selectedDeck = names.first ?? "Default"
            }
            statusMessage = "Loaded \(names.count) deck(s)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createDeck(named name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await anki.createDeck(trimmed)
            await refreshDecks()
            selectedDeck = trimmed
            statusMessage = "Created deck \"\(trimmed)\"."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Creates a subdeck under the given parent (or a top-level deck if parent is nil).
    func createSubdeck(under parent: String?, leaf: String) async {
        let leafTrimmed = leaf.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !leafTrimmed.isEmpty else { return }
        let full = parent.map { "\($0)::\(leafTrimmed)" } ?? leafTrimmed
        await createDeck(named: full)
    }

    // MARK: - Chat + card generation

    /// Builds the effective system prompt from the user's configurable template:
    /// substitutes {{noteKind}} and appends the strict-context instruction if enabled.
    private var systemPrompt: String {
        var prompt = settings.systemPromptTemplate
            .replacingOccurrences(of: "{{noteKind}}", with: noteKind.rawValue)
        if settings.constrainToContext {
            prompt += "\n\n" + AppSettings.constrainInstruction
        }
        return prompt
    }

    func sendDraft() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingAttachments
        guard !(text.isEmpty && attachments.isEmpty), !isSending else { return }
        guard !settings.selectedModel.isEmpty else {
            errorMessage = "Select a model in the sidebar first."
            return
        }
        draft = ""
        pendingAttachments = []
        messages.append(ChatMessage(role: .user, text: text, attachments: attachments))
        isSending = true
        defer { isSending = false }

        // Images from this turn get embedded into the cards it produces.
        let turnImages = attachments.filter { $0.isImage }

        var convo: [ChatMessage] = [ChatMessage(role: .system, text: systemPrompt)]
        convo.append(contentsOf: messages)

        // Insert a live assistant message that we fill in as deltas arrive.
        let assistant = ChatMessage(role: .assistant, text: "", model: settings.selectedModel)
        messages.append(assistant)
        let assistantID = assistant.id

        var answerRaw = ""     // content channel (may contain <think> tags)
        var reasoningRaw = ""  // dedicated reasoning channel, if any
        do {
            for try await delta in openAI.streamChat(model: settings.selectedModel, messages: convo) {
                answerRaw += delta.content
                reasoningRaw += delta.reasoning
                let (think, answer) = Self.splitThink(answerRaw)
                if let idx = messages.firstIndex(where: { $0.id == assistantID }) {
                    messages[idx].reasoning = Self.combine(reasoningRaw, think)
                    messages[idx].text = Self.liveVisible(answer)
                }
            }

            // Streaming finished: parse out the card block and finalize the bubble.
            let (think, answer) = Self.splitThink(answerRaw)
            let (visible, parsed) = CardParser.extract(from: answer)
            let newCards = parsed.map { proto -> NoteCard in
                var c = proto
                c.deck = selectedDeck
                c.imageAttachments = turnImages
                return c
            }
            cards.append(contentsOf: newCards)

            var shown = visible.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newCards.isEmpty {
                let imgNote = turnImages.isEmpty ? "" : " (image embedded in Extra)"
                let note = "\n\n📇 Added \(newCards.count) card(s) to the session\(imgNote)."
                shown = shown.isEmpty ? "Created \(newCards.count) card(s)\(imgNote)." : shown + note
            }
            if let idx = messages.firstIndex(where: { $0.id == assistantID }) {
                messages[idx].reasoning = Self.combine(reasoningRaw, think)
                messages[idx].text = shown.isEmpty ? "(no response)" : shown
            }
            if let first = newCards.first, selection.isEmpty {
                selection = [first.id]
            }
        } catch {
            errorMessage = error.localizedDescription
            if let idx = messages.firstIndex(where: { $0.id == assistantID }) {
                let (_, answer) = Self.splitThink(answerRaw)
                let partial = Self.liveVisible(answer).trimmingCharacters(in: .whitespacesAndNewlines)
                let prefix = partial.isEmpty ? "" : partial + "\n\n"
                messages[idx].text = prefix + "⚠️ \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Attachments

    func addAttachments(_ urls: [URL]) {
        let loaded = urls.compactMap(Attachment.load)
        pendingAttachments.append(contentsOf: loaded)
        let failed = urls.count - loaded.count
        if failed > 0 { errorMessage = "Could not read \(failed) file(s)." }
    }

    func removeAttachment(_ id: Attachment.ID) {
        pendingAttachments.removeAll { $0.id == id }
    }

    /// Stages an image pasted into the chat box, treating it like an attached file.
    func addPastedImage(_ image: NSImage) {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            errorMessage = "Could not read the pasted image."
            return
        }
        let att = Attachment(
            filename: "pasted-image-\(pendingAttachments.count + 1).png",
            kind: .image, data: png, mimeType: "image/png", extractedText: nil
        )
        pendingAttachments.append(att)
    }

    // MARK: - Stream text helpers

    /// While streaming, hide the trailing card JSON block so the user sees only prose.
    private static func liveVisible(_ full: String) -> String {
        if let r = full.range(of: "```anki", options: [.caseInsensitive, .backwards]) {
            let prose = String(full[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            return prose.isEmpty ? "📇 Generating cards…" : prose + "\n\n📇 Generating cards…"
        }
        return full
    }

    /// Separates inline `<think>…</think>` reasoning from the answer body.
    private static func splitThink(_ s: String) -> (reasoning: String, answer: String) {
        guard let open = s.range(of: "<think>") else { return ("", s) }
        let before = String(s[..<open.lowerBound])
        if let close = s.range(of: "</think>") {
            let reasoning = String(s[open.upperBound..<close.lowerBound])
            let after = String(s[close.upperBound...])
            return (reasoning, before + after)
        }
        // Still inside the think block (no closing tag yet).
        return (String(s[open.upperBound...]), before)
    }

    private static func combine(_ a: String, _ b: String) -> String {
        let parts = [a, b].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return parts.joined(separator: "\n")
    }

    // MARK: - Card editing

    /// The single card to show in the editor, or nil if zero/multiple are selected.
    var editingIndex: Int? {
        guard selection.count == 1, let id = selection.first else { return nil }
        return cards.firstIndex(where: { $0.id == id })
    }

    func delete(_ ids: Set<NoteCard.ID>) {
        cards.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
    }

    /// Duplicates the given cards (as unsent copies) and selects the new ones.
    func duplicate(_ ids: Set<NoteCard.ID>) {
        // Walk back-to-front so inserted copies don't shift later indices.
        let indices = cards.indices.filter { ids.contains(cards[$0].id) }.sorted(by: >)
        var newIDs: Set<NoteCard.ID> = []
        for idx in indices {
            var copy = cards[idx]
            copy.id = UUID()
            copy.sentToAnki = false
            copy.ankiNoteID = nil
            cards.insert(copy, at: idx + 1)
            newIDs.insert(copy.id)
        }
        if !newIDs.isEmpty { selection = newIDs }
    }

    /// Copies the text of the given cards to the clipboard.
    func copyText(_ ids: Set<NoteCard.ID>) {
        let ordered = cards.filter { ids.contains($0.id) }
        let blocks = ordered.map { card -> String in
            switch card.kind {
            case .basic:
                var s = "Front: \(card.front)\nBack: \(card.back)"
                if !card.extra.isEmpty { s += "\nExtra: \(card.extra)" }
                return s
            case .cloze:
                var s = "Text: \(card.clozeText)"
                if !card.extra.isEmpty { s += "\nBack Extra: \(card.extra)" }
                return s
            }
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(blocks.joined(separator: "\n\n"), forType: .string)
        statusMessage = "Copied \(ordered.count) card(s) to the clipboard."
    }

    func addBlankCard() {
        var c = NoteCard(kind: noteKind)
        c.deck = selectedDeck
        c.tags = []   // manual card; the #AI tag is for model-generated cards
        cards.append(c)
        selection = [c.id]
    }

    // MARK: - Send to Anki

    func sendToAnki(_ ids: Set<NoteCard.ID>) async {
        guard !ids.isEmpty, !isSendingToAnki else { return }
        isSendingToAnki = true
        defer { isSendingToAnki = false }

        var addedCount = 0
        var updatedCount = 0
        var failures: [String] = []

        for id in ids {
            guard let idx = cards.firstIndex(where: { $0.id == id }) else { continue }
            do {
                if cards[idx].sentToAnki, let noteID = cards[idx].ankiNoteID {
                    // Already in Anki: push edits to the existing note.
                    try await anki.updateNoteFields(id: noteID, fields: cards[idx].ankiFields)
                    updatedCount += 1
                } else {
                    // New note: ensure the target deck exists, then add.
                    try await anki.createDeck(cards[idx].deck)
                    let noteID = try await anki.addNote(cards[idx])
                    cards[idx].sentToAnki = true
                    cards[idx].ankiNoteID = noteID
                    addedCount += 1
                }
            } catch {
                failures.append("\"\(cards[idx].title)\": \(error.localizedDescription)")
            }
        }

        var summary: [String] = []
        if addedCount > 0 { summary.append("added \(addedCount)") }
        if updatedCount > 0 { summary.append("updated \(updatedCount)") }
        let summaryText = summary.isEmpty ? "nothing sent" : summary.joined(separator: ", ")

        if failures.isEmpty {
            statusMessage = "Anki: \(summaryText)."
        } else {
            errorMessage = "Anki: \(summaryText). Failed \(failures.count):\n" + failures.joined(separator: "\n")
        }
    }
}
