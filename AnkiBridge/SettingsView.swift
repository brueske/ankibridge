import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var state: AppState

    @State private var pingResult: String = ""
    @State private var ankiResult: String = ""

    var body: some View {
        TabView {
            connectionTab
                .tabItem { Label("Connections", systemImage: "network") }
            promptTab
                .tabItem { Label("Prompt", systemImage: "text.bubble") }
        }
        .frame(minWidth: 520, idealWidth: 580, minHeight: 440, idealHeight: 520)
    }

    // MARK: - Connections

    private var connectionTab: some View {
        Form {
            Section("Local model server (OpenAI-compatible)") {
                TextField("Base URL", text: $settings.serverBaseURL, prompt: Text("http://localhost:1234/v1"))
                TextField("API key (optional)", text: $settings.apiKey)
                HStack {
                    Button("Test & load models") {
                        Task {
                            await state.refreshModels()
                            pingResult = state.availableModels.isEmpty
                                ? "No models found."
                                : "OK — \(state.availableModels.count) model(s)."
                        }
                    }
                    Text(pingResult).font(.caption).foregroundStyle(.secondary)
                }
                Text("Include the version path (e.g. /v1). Works with LM Studio, llama.cpp server, vLLM, and Ollama's compatibility endpoint. Attaching images requires a vision-capable model.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("AnkiConnect") {
                TextField("URL", text: $settings.ankiConnectURL, prompt: Text("http://127.0.0.1:8765"))
                HStack {
                    Button("Test connection") {
                        Task {
                            do {
                                let v = try await AnkiConnectClient(urlString: settings.ankiConnectURL).version()
                                ankiResult = "Connected (API v\(v))."
                                await state.refreshDecks()
                            } catch {
                                ankiResult = error.localizedDescription
                            }
                        }
                    }
                    Text(ankiResult).font(.caption).foregroundStyle(.secondary)
                }
                Text("Anki must be running with the AnkiConnect add-on installed.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Prompt

    private var promptTab: some View {
        Form {
            Section("System prompt") {
                Text("Sent to the model on every request. Use {{noteKind}} where the current card type (Basic / Cloze) should appear. Keep the `anki` JSON block instructions if you want automatic card extraction to keep working.")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $settings.systemPromptTemplate)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 220)
                    .padding(6)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
                HStack {
                    Button("Reset to default") { settings.resetPromptToDefault() }
                    Spacer()
                }
            }

            Section("Context") {
                Toggle("Use only attached context (no outside knowledge)", isOn: $settings.constrainToContext)
                Text("When on, the model is told to build cards strictly from your messages and attached files/images, and to ask for more rather than invent facts. This toggle is also available beneath the chat box.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
