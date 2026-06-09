import Foundation

enum OpenAIError: LocalizedError {
    case badURL
    case http(Int, String)
    case decoding(String)
    case empty

    var errorDescription: String? {
        switch self {
        case .badURL: return "The server base URL is invalid."
        case .http(let code, let body): return "Server returned HTTP \(code): \(body)"
        case .decoding(let msg): return "Could not decode the server response: \(msg)"
        case .empty: return "The server returned an empty response."
        }
    }
}

/// Minimal client for an OpenAI-compatible chat server (LM Studio, llama.cpp,
/// vLLM, Ollama compat mode, etc.).
struct OpenAIClient {
    var baseURL: String
    var apiKey: String

    private func endpoint(_ path: String) -> URL? {
        let trimmed = baseURL.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: trimmed + path)
    }

    private func request(_ url: URL, method: String, body: Data? = nil) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body
        req.timeoutInterval = 120
        return req
    }

    // MARK: - Models

    private struct ModelsResponse: Decodable {
        struct Model: Decodable { let id: String }
        let data: [Model]
    }

    /// GET /models
    func listModels() async throws -> [String] {
        guard let url = endpoint("/models") else { throw OpenAIError.badURL }
        let (data, resp) = try await URLSession.shared.data(for: request(url, method: "GET"))
        try Self.checkStatus(resp, data)
        do {
            let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
            return decoded.data.map(\.id).sorted()
        } catch {
            throw OpenAIError.decoding(error.localizedDescription)
        }
    }

    // MARK: - Chat

    /// A message whose content is either a plain string or an array of parts
    /// (text + images), matching the OpenAI multimodal chat format.
    private struct Msg: Encodable {
        let role: String
        let content: Content

        enum Content: Encodable {
            case text(String)
            case parts([Part])

            func encode(to encoder: Encoder) throws {
                var c = encoder.singleValueContainer()
                switch self {
                case .text(let s): try c.encode(s)
                case .parts(let p): try c.encode(p)
                }
            }
        }

        struct Part: Encodable {
            struct ImageURL: Encodable { let url: String }
            let type: String
            var text: String? = nil
            var image_url: ImageURL? = nil
        }
    }

    /// Builds an API message from a chat message, embedding attached document text
    /// and images (for vision models).
    private static func makeMsg(_ m: ChatMessage) -> Msg {
        guard !m.attachments.isEmpty else {
            return Msg(role: m.role.rawValue, content: .text(m.text))
        }
        var textBlock = m.text
        for att in m.attachments where !att.isImage {
            if let t = att.extractedText, !t.isEmpty {
                textBlock += "\n\n--- Attached file: \(att.filename) ---\n\(t)"
            } else {
                textBlock += "\n\n[Attached file: \(att.filename) — binary, contents not readable as text]"
            }
        }
        var parts: [Msg.Part] = [Msg.Part(type: "text", text: textBlock)]
        for att in m.attachments where att.isImage {
            parts.append(Msg.Part(type: "image_url", image_url: .init(url: att.dataURL)))
        }
        return Msg(role: m.role.rawValue, content: .parts(parts))
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [Msg]
        let temperature: Double
        let stream: Bool
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }

    /// POST /chat/completions (non-streaming).
    func chat(model: String, messages: [ChatMessage], temperature: Double = 0.4) async throws -> String {
        guard let url = endpoint("/chat/completions") else { throw OpenAIError.badURL }
        let payload = ChatRequest(
            model: model,
            messages: messages.map(Self.makeMsg),
            temperature: temperature,
            stream: false
        )
        let body = try JSONEncoder().encode(payload)
        let (data, resp) = try await URLSession.shared.data(for: request(url, method: "POST", body: body))
        try Self.checkStatus(resp, data)
        do {
            let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
            guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
                throw OpenAIError.empty
            }
            return content
        } catch let e as OpenAIError {
            throw e
        } catch {
            throw OpenAIError.decoding(error.localizedDescription)
        }
    }

    // MARK: - Streaming chat

    /// One streamed increment: answer content and/or reasoning content.
    struct StreamDelta: Sendable {
        var content: String = ""
        var reasoning: String = ""
    }

    private struct StreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
                // Different servers name the reasoning channel differently.
                let reasoning_content: String?
                let reasoning: String?
            }
            let delta: Delta
        }
        let choices: [Choice]
    }

    /// POST /chat/completions with stream:true. Yields content/reasoning deltas as they arrive.
    func streamChat(model: String, messages: [ChatMessage], temperature: Double = 0.4)
        -> AsyncThrowingStream<StreamDelta, Error>
    {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let url = endpoint("/chat/completions") else { throw OpenAIError.badURL }
                    let payload = ChatRequest(
                        model: model,
                        messages: messages.map(Self.makeMsg),
                        temperature: temperature,
                        stream: true
                    )
                    let body = try JSONEncoder().encode(payload)
                    var req = request(url, method: "POST", body: body)
                    req.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                    if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        var errBody = ""
                        for try await line in bytes.lines {
                            errBody += line + "\n"
                            if errBody.count > 800 { break }
                        }
                        throw OpenAIError.http(http.statusCode, String(errBody.prefix(500)))
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let chunk = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if chunk == "[DONE]" { break }
                        if chunk.isEmpty { continue }
                        guard let d = chunk.data(using: .utf8),
                              let decoded = try? JSONDecoder().decode(StreamChunk.self, from: d),
                              let delta = decoded.choices.first?.delta
                        else { continue }
                        var out = StreamDelta()
                        if let c = delta.content { out.content = c }
                        if let r = delta.reasoning_content ?? delta.reasoning { out.reasoning = r }
                        if !out.content.isEmpty || !out.reasoning.isEmpty {
                            continuation.yield(out)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func checkStatus(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw OpenAIError.http(http.statusCode, String(body.prefix(500)))
        }
    }
}
