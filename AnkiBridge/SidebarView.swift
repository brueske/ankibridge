import SwiftUI

private enum SidebarTab: String, CaseIterable, Identifiable {
    case model = "Model"
    case decks = "Decks"
    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .model: return "cpu"
        case .decks: return "rectangle.stack"
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject var state: AppState
    @State private var tab: SidebarTab = .model

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(SidebarTab.allCases) { t in
                    Label(t.rawValue, systemImage: t.systemImage).tag(t)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)

            Divider()

            switch tab {
            case .model: ModelTab()
            case .decks: DeckTab()
            }
        }
    }
}

// MARK: - Model tab

private struct ModelTab: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Local Models").font(.headline)
                    Spacer()
                    Button {
                        Task { await state.refreshModels() }
                    } label: {
                        if state.isLoadingModels {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderless)
                    .help("Fetch models from the server")
                }
                Text("Server: \(settings.serverBaseURL)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if state.availableModels.isEmpty {
                ContentUnavailableView {
                    Label("No models loaded", systemImage: "cpu")
                } description: {
                    Text("Set your server address in Settings, then refresh.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(state.availableModels, id: \.self, selection: Binding(
                    get: { settings.selectedModel },
                    set: { if let v = $0 { settings.selectedModel = v } }
                )) { model in
                    HStack(spacing: 6) {
                        Image(systemName: settings.selectedModel == model ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(settings.selectedModel == model ? Color.accentColor : .secondary)
                        Text(model)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .tag(model)
                    .contentShape(Rectangle())
                    .onTapGesture { settings.selectedModel = model }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if state.availableModels.isEmpty { await state.refreshModels() }
        }
    }
}

// MARK: - Deck tab

private struct DeckTab: View {
    @EnvironmentObject var state: AppState
    @State private var newDeckName = ""
    @State private var showingNewDeck = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Anki Decks").font(.headline)
                    Spacer()
                    Button {
                        Task { await state.refreshDecks() }
                    } label: {
                        if state.isLoadingDecks {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderless)
                    .help("Reload decks from Anki")
                }
                Text("Target: \(state.selectedDeck)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if state.deckTree.isEmpty {
                ContentUnavailableView {
                    Label("No decks", systemImage: "rectangle.stack")
                } description: {
                    Text("Make sure Anki is running with AnkiConnect, then reload.")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $state.selectedDeck) {
                    OutlineGroup(state.deckTree, children: \.childrenOrNil) { node in
                        Label(node.name, systemImage: "folder")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .tag(node.id)
                            .contextMenu {
                                Button("Add subdeck…") {
                                    showingNewDeck = true
                                    pendingParent = node.id
                                }
                                Button("Use as target") { state.selectedDeck = node.id }
                            }
                    }
                }
                .listStyle(.sidebar)
            }

            Divider()
            HStack {
                Button {
                    pendingParent = nil
                    showingNewDeck = true
                } label: {
                    Label("New folder", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.borderless)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            if state.deckTree.isEmpty { await state.refreshDecks() }
        }
        .alert("New deck", isPresented: $showingNewDeck) {
            TextField("Deck name", text: $newDeckName)
            Button("Create") {
                let leaf = newDeckName
                newDeckName = ""
                Task { await state.createSubdeck(under: pendingParent, leaf: leaf) }
            }
            Button("Cancel", role: .cancel) { newDeckName = "" }
        } message: {
            if let p = pendingParent {
                Text("Creating a subdeck under \"\(p)\".")
            } else {
                Text("Creating a top-level deck.")
            }
        }
    }

    @State private var pendingParent: String? = nil
}

private extension DeckNode {
    /// OutlineGroup expects nil (not empty) for leaves to hide the disclosure chevron.
    var childrenOrNil: [DeckNode]? { children.isEmpty ? nil : children }
}
