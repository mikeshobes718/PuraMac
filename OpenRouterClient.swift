import Foundation

enum AIError: Error {
    case message(String)
}

struct ChatMessage {
    var role: String
    var content: String
}

final class OpenRouterClient {
    static let shared = OpenRouterClient()

    let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!
    let keysPath = "/Users/mike/Documents/Keys/.env"
    let defaultModel = "google/gemini-3.7-flash"
    let modelOptions = [
        "google/gemini-3.7-flash",
        "openai/gpt-4o-mini",
        "google/gemini-3.5-flash",
        "google/gemini-3-flash-preview",
        "openai/gpt-4.1-mini",
        "anthropic/claude-sonnet-4.5"
    ]

    func complete(model: String, system: String, user: String, maxTokens: Int = 1400, completion: @escaping (Result<String, AIError>) -> Void) {
        var messages: [[String: String]] = [["role": "system", "content": system]]
        messages.append(["role": "user", "content": user])
        send(model: model, messages: messages, maxTokens: maxTokens, completion: completion)
    }

    func complete(model: String, system: String, history: [ChatMessage], user: String, completion: @escaping (Result<String, AIError>) -> Void) {
        var messages: [[String: String]] = [["role": "system", "content": system]]
        for entry in history {
            messages.append(["role": entry.role, "content": entry.content])
        }
        messages.append(["role": "user", "content": user])
        send(model: model, messages: messages, maxTokens: 1400, completion: completion)
    }

    private func send(model: String, messages: [[String: String]], maxTokens: Int, completion: @escaping (Result<String, AIError>) -> Void) {
        guard let key = Self.loadOpenRouterKey(keysPath: keysPath) else {
            completion(.failure(AIError.message("OPENROUTER_API_KEY not found in " + keysPath)))
            return
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "temperature": 0.3,
            "max_tokens": maxTokens,
            "messages": messages
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(AIError.message("Could not encode request")))
            return
        }
        request.httpBody = data

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(AIError.message(error.localizedDescription)))
                return
            }
            guard let http = response as? HTTPURLResponse, let data = data else {
                completion(.failure(AIError.message("No response from OpenRouter")))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                let bodyText = String(data: data, encoding: .utf8) ?? ""
                completion(.failure(AIError.message("HTTP \(http.statusCode): " + String(bodyText.prefix(200)))))
                return
            }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = obj["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                completion(.failure(AIError.message("Unexpected response shape")))
                return
            }
            completion(.success(content))
        }.resume()
    }

    static func loadOpenRouterKey(keysPath: String) -> String? {
        guard let text = try? String(contentsOfFile: keysPath, encoding: .utf8) else { return nil }
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("OPENROUTER_API_KEY=") {
                var value = String(trimmed.dropFirst("OPENROUTER_API_KEY=".count))
                value = value.trimmingCharacters(in: .whitespaces)
                value = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                return value.isEmpty ? nil : value
            }
        }
        return nil
    }
}
