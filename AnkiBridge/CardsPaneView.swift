import SwiftUI
import AppKit

struct CardsPaneView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HSplitView {
            cardList
                .frame(minWidth: 220, idealWidth: 280, maxWidth: 420)
            editor
                .frame(minWidth: 320)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Left: session card list

    private var cardList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Session Cards").font(.headline)
                Spacer()
                Text("\(state.cards.count)")
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    state.addBlankCard()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("Add a blank card")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if state.cards.isEmpty {
                Spacer()
                Text("Cards generated this session will appear here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            } else {
                List(selection: $state.selection) {
                    ForEach(state.cards) { card in
                        CardRow(card: card)
                            .tag(card.id)
                    }
                }
                .listStyle(.inset)
                .contextMenu(forSelectionType: NoteCard.ID.self) { ids in
                    cardMenu(for: ids)
                } primaryAction: { _ in }
            }
        }
    }

    /// Builds the right-click menu. `ids` is the set the menu applies to: a single
    /// right-clicked row if it's outside the selection, otherwise the whole selection.
    @ViewBuilder
    private func cardMenu(for ids: Set<NoteCard.ID>) -> some View {
        if ids.isEmpty {
            Button("Add Card") { state.addBlankCard() }
        } else {
            Button("Send to Anki") { Task { await state.sendToAnki(ids) } }
                .disabled(state.isSendingToAnki)
            Button("Duplicate") { state.duplicate(ids) }
            Button("Copy") { state.copyText(ids) }
            Divider()
            Button("Delete", role: .destructive) { state.delete(ids) }
        }
    }

    // MARK: - Right: editor + send button

    private var editor: some View {
        VStack(spacing: 0) {
            if let idx = state.editingIndex {
                CardEditor(card: $state.cards[idx], decks: allDeckNames)
            } else {
                Spacer()
                Text(state.selection.count > 1
                     ? "\(state.selection.count) cards selected. Select a single card to edit it."
                     : "Select a card to preview and edit it.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            }

            Divider()
            sendBar
        }
    }

    private var sendBar: some View {
        HStack {
            Text("\(state.selection.count) selected")
                .font(.caption).foregroundStyle(.secondary)
            Spacer()
            if state.isSendingToAnki {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await state.sendToAnki(state.selection) }
            } label: {
                Label("Send to Anki", systemImage: "tray.and.arrow.down")
            }
            .keyboardShortcut(.return, modifiers: [.command, .shift])
            .disabled(state.selection.isEmpty || state.isSendingToAnki)
        }
        .padding(12)
    }

    private var allDeckNames: [String] {
        var names: [String] = []
        func walk(_ nodes: [DeckNode]) {
            for n in nodes { names.append(n.id); walk(n.children) }
        }
        walk(state.deckTree)
        if !names.contains(state.selectedDeck) { names.insert(state.selectedDeck, at: 0) }
        if names.isEmpty { names = ["Default"] }
        return names
    }
}

// MARK: - Row

private struct CardRow: View {
    let card: NoteCard

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(card.title)
                    .lineLimit(2)
                Text(card.kind.rawValue + " · " + card.deck)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if card.sentToAnki {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("In Anki")
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Editor

private struct CardEditor: View {
    @Binding var card: NoteCard
    let decks: [String]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Picker("Type", selection: $card.kind) {
                        ForEach(NoteKind.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .frame(width: 200)
                    Spacer()
                    if card.sentToAnki {
                        Label("Sent", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                    }
                }

                Picker("Deck", selection: $card.deck) {
                    ForEach(decks, id: \.self) { Text($0).tag($0) }
                }

                switch card.kind {
                case .basic:
                    field("Front", text: $card.front)
                    field("Back", text: $card.back)
                    field("Extra", text: $card.extra, hint: "appended to Back on send")
                case .cloze:
                    field("Text", text: $card.clozeText, hint: "Use {{c1::…}} for cloze deletions")
                    field("Back Extra", text: $card.extra)
                }

                if !card.imageAttachments.isEmpty {
                    attachedImages
                }

                tagsField

                if card.sentToAnki {
                    Text("Already in Anki. Edit the fields, re-select this card, and press Send to Anki to push the changes as an update. (Deck and tag changes are not applied on update.)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
    }

    private func field(_ label: String, text: Binding<String>, hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline).bold()
                if let hint { Text(hint).font(.caption2).foregroundStyle(.secondary) }
            }
            TextEditor(text: text)
                .font(.body)
                .frame(minHeight: 70)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
        }
    }

    private var attachedImages: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Attached image\(card.imageAttachments.count > 1 ? "s" : "")")
                .font(.subheadline).bold()
            Text("Embedded into the \(card.extraFieldName) field when sent to Anki.")
                .font(.caption2).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(card.imageAttachments) { att in
                        if let img = NSImage(data: att.data) {
                            Image(nsImage: img)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 120)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2)))
                        }
                    }
                }
            }
        }
    }

    private var tagsField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tags").font(.subheadline).bold()
            TextField("space-separated tags", text: Binding(
                get: { card.tags.joined(separator: " ") },
                set: { card.tags = $0.split(separator: " ").map(String.init) }
            ))
            .textFieldStyle(.roundedBorder)
        }
    }
}
