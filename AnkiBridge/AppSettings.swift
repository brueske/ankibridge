import Foundation
import Combine

/// User-configurable connection settings, persisted in UserDefaults.
final class AppSettings: ObservableObject {
    /// Base URL of the OpenAI-compatible server, including the version path.
    /// e.g. http://localhost:1234/v1 (LM Studio), http://localhost:11434/v1 (Ollama compat).
    @Published var serverBaseURL: String {
        didSet { defaults.set(serverBaseURL, forKey: Keys.serverBaseURL) }
    }

    /// Optional bearer token. Many local servers ignore this; leave blank if unused.
    @Published var apiKey: String {
        didSet { defaults.set(apiKey, forKey: Keys.apiKey) }
    }

    /// AnkiConnect endpoint. Default is the AnkiConnect plugin's default.
    @Published var ankiConnectURL: String {
        didSet { defaults.set(ankiConnectURL, forKey: Keys.ankiConnectURL) }
    }

    /// Last selected model id.
    @Published var selectedModel: String {
        didSet { defaults.set(selectedModel, forKey: Keys.selectedModel) }
    }

    /// The editable system prompt sent to the model. Supports the `{{noteKind}}`
    /// placeholder, replaced with "Basic" or "Cloze" at send time.
    @Published var systemPromptTemplate: String {
        didSet { defaults.set(systemPromptTemplate, forKey: Keys.systemPromptTemplate) }
    }

    /// When on, the model is instructed to use only the user's messages and
    /// attached files/images — no outside knowledge.
    @Published var constrainToContext: Bool {
        didSet { defaults.set(constrainToContext, forKey: Keys.constrainToContext) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let serverBaseURL = "serverBaseURL"
        static let apiKey = "apiKey"
        static let ankiConnectURL = "ankiConnectURL"
        static let selectedModel = "selectedModel"
        static let systemPromptTemplate = "systemPromptTemplate"
        static let constrainToContext = "constrainToContext"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.serverBaseURL = defaults.string(forKey: Keys.serverBaseURL) ?? "http://localhost:1234/v1"
        self.apiKey = defaults.string(forKey: Keys.apiKey) ?? ""
        self.ankiConnectURL = defaults.string(forKey: Keys.ankiConnectURL) ?? "http://127.0.0.1:8765"
        self.selectedModel = defaults.string(forKey: Keys.selectedModel) ?? ""
        self.systemPromptTemplate = defaults.string(forKey: Keys.systemPromptTemplate) ?? AppSettings.defaultSystemPrompt
        self.constrainToContext = defaults.object(forKey: Keys.constrainToContext) as? Bool ?? false
    }

    func resetPromptToDefault() {
        systemPromptTemplate = AppSettings.defaultSystemPrompt
    }

    /// The instruction appended when "constrain to context" is enabled.
    static let constrainInstruction = """
        STRICT CONTEXT MODE: Use ONLY information explicitly present in the user's messages \
        and the attached files/images. Do not add any outside or prior knowledge. If the \
        provided material is insufficient to make a correct card, say so and ask for more \
        rather than inventing facts.
        """

    static let defaultSystemPrompt = """
        You are AnkiBridge, an assistant that turns the user's study material into Anki flashcards.

        Workflow:
        - If the request is ambiguous or you need more detail, ASK concise clarifying questions in plain prose. Do not invent cards prematurely.
        - When you have enough information, produce flashcards.

        The user currently wants {{noteKind}} cards.

        When you output cards, end your message with a single fenced code block tagged `anki`
        containing a JSON array. Each element must be an object:
          - For Basic: {"type":"basic","front":"<question/prompt>","back":"<answer>"}
          - For Cloze: {"type":"cloze","text":"<sentence with {{c1::hidden}} deletions>","extra":"<optional extra>"}
        Use minimal, well-formed HTML only where helpful (e.g. <br>, <b>). Do not wrap the JSON in prose.
        You may include a short sentence before the code block summarizing what you made.
        If you are only asking questions, do NOT include the code block.
        """
}
