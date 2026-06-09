# AnkiBridge

A macOS (SwiftUI) app that bridges a **local OpenAI-compatible model server** and **Anki** (via the AnkiConnect add-on). Describe what you want to study, the model asks clarifying questions and generates flashcards, you review/edit them, then push the selected ones into Anki.

## Layout

```
AnkiBridge.xcodeproj      ← open this in Xcode and press Run
AnkiBridge/
  AnkiBridgeApp.swift     app entry + Settings scene
  ContentView.swift       NavigationSplitView + top Basic/Cloze toggle + VSplit
  SidebarView.swift       left sidebar: "Model" tab and "Decks" tab
  ChatView.swift          top half: chat with the model
  CardsPaneView.swift     bottom half: session-card list + editor + "Send to Anki"
  SettingsView.swift      server / AnkiConnect settings
  AppState.swift          orchestration (chat, card parsing, Anki push)
  AppSettings.swift       persisted settings (UserDefaults)
  Models.swift            ChatMessage, NoteCard, DeckNode (deck tree)
  OpenAIClient.swift      /v1/models + /v1/chat/completions
  AnkiConnectClient.swift deckNames / createDeck / addNote
  CardParser.swift        extracts the model's ```anki JSON block into cards
gen_proj.py               regenerates the .xcodeproj if needed
```

## Requirements

- Xcode 16+ (built/tested with Xcode 26.5), macOS 14+ deployment target.
- A local OpenAI-compatible server (LM Studio, llama.cpp server, vLLM, or Ollama's `/v1` compat endpoint).
- Anki running with the [AnkiConnect](https://foosoft.net/projects/anki-connect/) add-on.

## Setup

1. Open `AnkiBridge.xcodeproj` in Xcode and Run (⌘R).
2. Open **Settings** (⌘, or the gear in the toolbar):
   - **Base URL** of your model server, including the version path, e.g. `http://localhost:1234/v1`.
   - **AnkiConnect URL** (default `http://127.0.0.1:8765`). Use *Test connection*.
3. In the sidebar **Model** tab, pick a model. In the **Decks** tab, browse your deck
   tree, create folders/subdecks, and select one as the output target.
4. Toggle **Basic / Cloze** at the top of the window to tell the model which card type to make.
5. Chat in the top half. Generated cards land in the bottom-left list.
6. Click a card to preview/edit its fields. Select cards with normal macOS gestures
   (click, ⇧-click for a range, ⌘-click to toggle), then press **Send to Anki** (⌘⇧↩)
   at the lower right to send the selection. Sent cards get a green check.
7. Right-click a card (or selection) for **Send to Anki**, **Duplicate**, **Copy**
   (card text to clipboard), and **Delete**.

## How card generation works

The system prompt instructs the model to ask clarifying questions in prose, and—once
ready—to append a single fenced ` ```anki ` block containing a JSON array of cards.
`CardParser` extracts that block, hides it from the chat transcript, and turns each
object into an editable `NoteCard`. Basic cards map to Anki's `Basic` note type
(`Front`/`Back`); Cloze cards map to `Cloze` (`Text`/`Back Extra`). Every
model-generated card is tagged **`#AI`**.

## Attachments, prompt, reasoning, context-only

- **Attachments:** the paperclip in the chat box attaches images, PDFs, or text/other
  files. Image bytes are sent to the model as data URLs (needs a vision model); PDF and
  text contents are extracted (PDFKit / UTF-8) and appended as context. **Images attached
  to a turn are embedded into the produced card's Extra field** (`Back Extra` for Cloze,
  `Back` for Basic) via AnkiConnect's media support.
- **Configurable prompt:** Settings → *Prompt* shows and lets you edit the full system
  prompt. `{{noteKind}}` is replaced with the current card type. *Reset to default* restores it.
- **Reasoning box:** if the model emits reasoning (either `<think>…</think>` in the
  content or a `reasoning_content` stream channel), it's shown in a collapsible
  **Thinking** box above the answer.
- **Context-only mode:** the checkbox under the chat box (also in Settings) tells the
  model to use only your messages and attachments — no outside knowledge.

## Notes & limitations

- The app is **sandboxed with the network-client entitlement**, so it can reach
  `localhost` servers but nothing more.
- **Streaming:** chat responses stream in token-by-token (SSE, `stream:true`). The
  trailing ```anki card block is hidden while it streams and parsed once complete.
- **Post-send updates:** a card that's already in Anki keeps a green check but can
  still be re-selected. Editing its fields and pressing *Send to Anki* again pushes
  the changes via AnkiConnect `updateNoteFields`. (Field updates only — deck/tag
  changes are not applied on update.)
