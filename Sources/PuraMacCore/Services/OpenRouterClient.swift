import Foundation

public struct ChatMessage: Sendable, Equatable, Identifiable, Codable {
    public enum Role: String, Sendable, Codable { case system, user, assistant }

    public var id: UUID
    public var role: Role
    public var text: String
    public var date: Date

    public init(id: UUID = UUID(), role: Role, text: String, date: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.date = date
    }
}

public struct AIModel: Sendable, Identifiable, Hashable, Codable {
    public var id: String
    public var name: String
    public var contextLength: Int?
    public var promptPricePerMillion: Double?

    public var subtitle: String {
        var parts: [String] = []
        if let contextLength { parts.append("\(contextLength / 1000)K context") }
        if let promptPricePerMillion {
            parts.append(promptPricePerMillion == 0
                ? "Free"
                : "$\(String(format: "%.2f", promptPricePerMillion))/M in")
        }
        return parts.joined(separator: " · ")
    }
}

public enum AIError: Error, LocalizedError, Equatable {
    case missingKey
    case http(status: Int, body: String)
    case transport(String)
    case malformedResponse
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .missingKey:
            return "No OpenRouter API key yet. Add one in Settings to use the assistant."
        case .http(let status, let body):
            if status == 401 { return "OpenRouter rejected the API key (401). Check it in Settings." }
            if status == 402 { return "This OpenRouter account is out of credit (402)." }
            if status == 429 { return "OpenRouter is rate limiting this key (429). Try again shortly." }
            return "OpenRouter returned HTTP \(status): \(body.prefix(200))"
        case .transport(let message):
            return "Could not reach OpenRouter: \(message)"
        case .malformedResponse:
            return "OpenRouter returned a response PuraMac could not read."
        case .cancelled:
            return "Cancelled."
        }
    }
}

public actor OpenRouterClient {
    public static let shared = OpenRouterClient()

    private let completionsURL = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    private let modelsURL = URL(string: "https://openrouter.ai/api/v1/models")!
    private let session: URLSession
    private var cachedModels: [AIModel]?
    private var cachedAt: Date?

    public static let defaultModel = "anthropic/claude-haiku-4.5"

    /// Only used when the live catalogue cannot be reached, so a stale entry here
    /// degrades to a bad default rather than a broken picker.
    public static let fallbackModels: [AIModel] = [
        AIModel(id: "anthropic/claude-haiku-4.5", name: "Claude Haiku 4.5"),
        AIModel(id: "anthropic/claude-sonnet-4.5", name: "Claude Sonnet 4.5"),
        AIModel(id: "openai/gpt-4o-mini", name: "GPT-4o mini"),
        AIModel(id: "google/gemini-2.0-flash-001", name: "Gemini 2.0 Flash")
    ]

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: Model catalogue

    /// Fetched live so the picker never drifts out of date the way a hardcoded
    /// list does. Cached for an hour.
    public func models(forceRefresh: Bool = false) async -> [AIModel] {
        if !forceRefresh, let cachedModels, let cachedAt,
           Date().timeIntervalSince(cachedAt) < 3600 {
            return cachedModels
        }
        do {
            var request = URLRequest(url: modelsURL)
            request.timeoutInterval = 20
            applyAttribution(to: &request)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let entries = object["data"] as? [[String: Any]] else {
                return cachedModels ?? Self.fallbackModels
            }
            let parsed: [AIModel] = entries.compactMap { entry in
                guard let id = entry["id"] as? String else { return nil }
                let pricing = entry["pricing"] as? [String: Any]
                let promptPrice = (pricing?["prompt"] as? String).flatMap(Double.init)
                return AIModel(
                    id: id,
                    name: entry["name"] as? String ?? id,
                    contextLength: entry["context_length"] as? Int,
                    promptPricePerMillion: promptPrice.map { $0 * 1_000_000 }
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            guard !parsed.isEmpty else { return cachedModels ?? Self.fallbackModels }
            cachedModels = parsed
            cachedAt = Date()
            return parsed
        } catch {
            Log.ai.error("Model catalogue fetch failed: \(error.localizedDescription, privacy: .public)")
            return cachedModels ?? Self.fallbackModels
        }
    }

    // MARK: Completion

    public func complete(
        model: String,
        system: String,
        history: [ChatMessage] = [],
        user: String,
        maxTokens: Int = 1400
    ) async throws -> String {
        var text = ""
        for try await chunk in stream(model: model, system: system, history: history, user: user, maxTokens: maxTokens) {
            text += chunk
        }
        return text
    }

    /// Streamed so the assistant starts answering immediately instead of blocking
    /// on a whole completion.
    public nonisolated func stream(
        model: String,
        system: String,
        history: [ChatMessage] = [],
        user: String,
        maxTokens: Int = 1400
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try await self.makeRequest(
                        model: model, system: system, history: history,
                        user: user, maxTokens: maxTokens)
                    let (bytes, response) = try await self.session.bytes(for: request)

                    guard let http = response as? HTTPURLResponse else {
                        throw AIError.malformedResponse
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        var body = ""
                        for try await line in bytes.lines {
                            body += line
                            if body.count > 600 { break }
                        }
                        throw AIError.http(status: http.statusCode, body: body)
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = object["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let fragment = delta["content"] as? String,
                              !fragment.isEmpty else { continue }
                        continuation.yield(fragment)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: AIError.cancelled)
                } catch let error as AIError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: AIError.transport(error.localizedDescription))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeRequest(
        model: String, system: String, history: [ChatMessage], user: String, maxTokens: Int
    ) throws -> URLRequest {
        guard let key = Credentials.openRouterKey, !key.isEmpty else { throw AIError.missingKey }

        var payload: [[String: String]] = [["role": "system", "content": system]]
        for entry in history where entry.role != .system {
            payload.append(["role": entry.role.rawValue, "content": entry.text])
        }
        payload.append(["role": "user", "content": user])

        var request = URLRequest(url: completionsURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAttribution(to: &request)
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "temperature": 0.3,
            "max_tokens": maxTokens,
            "stream": true,
            "messages": payload
        ])
        return request
    }

    private nonisolated func applyAttribution(to request: inout URLRequest) {
        request.setValue("https://github.com/mikeshobes718/PuraMac", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("PuraMac", forHTTPHeaderField: "X-Title")
    }
}
