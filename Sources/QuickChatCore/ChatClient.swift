import Foundation

public enum StreamEvent: Equatable, Sendable {
    case content(String)
    case reasoning(String)
}

public enum ChatError: LocalizedError {
    case badURL
    case badResponse
    case http(Int, String?)
    case server(String)

    public var errorDescription: String? {
        switch self {
        case .badURL: return "The endpoint URL is not valid."
        case .badResponse: return "The server sent an unexpected response."
        case .http(let code, let msg):
            if let msg, !msg.isEmpty { return "\(msg) (HTTP \(code))" }
            switch code {
            case 401, 403: return "The API key was rejected (HTTP \(code))."
            case 404: return "Endpoint or model not found (HTTP 404)."
            case 429: return "Rate limited (HTTP 429)."
            default: return "The server returned HTTP \(code)."
            }
        case .server(let msg): return msg
        }
    }
}

/// Parsing of one line of an OpenAI-style server-sent-events stream.
public enum SSE {
    public enum Line: Equatable {
        case events([StreamEvent])
        case done
        case error(String)
        case ignore
    }

    public static func parse(line raw: String) -> Line {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("data:") else { return .ignore }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return .done }
        guard let data = payload.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return .ignore }

        if let message = errorMessage(in: obj) { return .error(message) }

        guard let choice = (obj["choices"] as? [[String: Any]])?.first else { return .ignore }
        let delta = (choice["delta"] as? [String: Any]) ?? (choice["message"] as? [String: Any]) ?? [:]
        var events: [StreamEvent] = []
        if let r = (delta["reasoning_content"] as? String) ?? (delta["reasoning"] as? String), !r.isEmpty {
            events.append(.reasoning(r))
        }
        if let c = delta["content"] as? String, !c.isEmpty {
            events.append(.content(c))
        }
        return events.isEmpty ? .ignore : .events(events)
    }

    /// Extracts `error.message` (or `error` / `message` strings) from a JSON object.
    static func errorMessage(in obj: [String: Any]) -> String? {
        if let e = obj["error"] as? [String: Any] { return (e["message"] as? String) ?? "Unknown server error" }
        if let e = obj["error"] as? String { return e }
        return nil
    }

    public static func errorMessage(from body: Data) -> String? {
        guard let obj = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            let text = String(data: body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (text?.isEmpty == false && text!.count < 300) ? text : nil
        }
        return errorMessage(in: obj) ?? (obj["message"] as? String)
    }
}

public enum ChatClient {
    public static func makeRequest(baseURL: String, apiKey: String?, model: String,
                                   effort: String?, messages: [ChatMessage]) throws -> URLRequest {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard let url = URL(string: base + "/chat/completions"), url.scheme?.hasPrefix("http") == true
        else { throw ChatError.badURL }

        var body: [String: Any] = [
            "model": model,
            "stream": true,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
        ]
        if let effort { body["reasoning_effort"] = effort }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        if let apiKey, !apiKey.isEmpty { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    /// Streams a chat completion. Cancelling the consuming task cancels the request.
    public static func stream(baseURL: String, apiKey: String?, model: String, effort: String?,
                              messages: [ChatMessage], session: URLSession = .shared)
        -> AsyncThrowingStream<StreamEvent, Error>
    {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try makeRequest(baseURL: baseURL, apiKey: apiKey, model: model,
                                                  effort: effort, messages: messages)
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw ChatError.badResponse }

                    guard (200..<300).contains(http.statusCode) else {
                        var body = Data()
                        for try await b in bytes { body.append(b); if body.count > 8192 { break } }
                        throw ChatError.http(http.statusCode, SSE.errorMessage(from: body))
                    }

                    for try await line in bytes.lines {
                        switch SSE.parse(line: line) {
                        case .events(let events): events.forEach { continuation.yield($0) }
                        case .done: continuation.finish(); return
                        case .error(let message): throw ChatError.server(message)
                        case .ignore: break
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
}
