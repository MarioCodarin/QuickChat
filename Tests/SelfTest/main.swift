import Foundation
import QuickChatCore

// A tiny dependency-free test harness (see Package.swift for why).
nonisolated(unsafe) var failures = 0
nonisolated(unsafe) var checks = 0

func check(_ ok: Bool, _ what: String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("  ✗ FAIL (line \(line)): \(what)") }
}
func eq<T: Equatable>(_ a: T, _ b: T, _ what: String, line: Int = #line) {
    check(a == b, "\(what): got \(a), expected \(b)", line: line)
}
func section(_ name: String) { print("• \(name)") }

let fixtureURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/opencode.json")
let fixture = try! String(contentsOf: fixtureURL, encoding: .utf8)

// MARK: ConfigImporter

section("importer: your opencode config")
do {
    let result = try ConfigImporter.parse(fixture)
    eq(result.endpoints.count, 1, "provider count")
    eq(result.defaultModel, "refuseless/glm-5.3-abliterated", "default model")
    let endpoint = result.endpoints[0].endpoint
    eq(endpoint.name, "Refuseless", "name")
    eq(endpoint.baseURL, "https://api.refuseless.com/v1", "baseURL")
    eq(endpoint.models.count, 9, "model count")
    let glm = endpoint.models.first { $0.id == "glm-5.3-abliterated" }
    eq(glm?.name, "GLM 5.3 Abliterated", "display name")
    eq(glm?.variants.map(\.id) ?? [], ["low", "high", "max"], "disabled `medium` hidden, ordered by effort")
    let ds = endpoint.models.first { $0.id == "deepseek-v4.1-flash-fast" }
    eq(ds?.variants.map(\.id) ?? [], ["off", "low", "high", "max"], "deepseek variants")
    eq(ds?.variants.first?.effort, "off", "effort value")
} catch { check(false, "parse threw \(error)") }

section("importer: JSONC + fragments")
do {
    let text = """
    {
      // a comment with a url: https://example.com
      "my": { "options": { "baseURL": "http://localhost:11434/v1", }, "models": { "llama": {}, }, },
    }
    """
    let r = try ConfigImporter.parse(text)
    eq(r.endpoints.first?.endpoint.baseURL, "http://localhost:11434/v1", "fragment baseURL")
    eq(r.endpoints.first?.endpoint.models.first?.id, "llama", "fragment model")
} catch { check(false, "fragment threw \(error)") }

section("importer: rejects garbage, ignores {env:} keys")
check((try? ConfigImporter.parse("hello")) == nil, "garbage text rejected")
check((try? ConfigImporter.parse(#"{"a": 1}"#)) == nil, "no providers rejected")
let envText = #"{"provider":{"p":{"options":{"baseURL":"https://x/v1","apiKey":"{env:KEY}"}}}}"#
check((try? ConfigImporter.parse(envText))?.endpoints[0].apiKey == nil, "{env:KEY} not stored as a key")

// MARK: SSE + request

section("sse parsing")
eq(SSE.parse(line: #"data: {"choices":[{"delta":{"content":"Hi"}}]}"#), .events([.content("Hi")]), "content delta")
eq(SSE.parse(line: #"data: {"choices":[{"delta":{"reasoning_content":"hmm"}}]}"#), .events([.reasoning("hmm")]), "reasoning delta")
eq(SSE.parse(line: "data: [DONE]"), .done, "done")
eq(SSE.parse(line: ": keep-alive"), .ignore, "comment line")
eq(SSE.parse(line: #"data: {"choices":[{"delta":{"role":"assistant"}}]}"#), .ignore, "role-only delta")
eq(SSE.parse(line: #"data: {"error":{"message":"boom"}}"#), .error("boom"), "error payload")

section("request shape")
do {
    let req = try ChatClient.makeRequest(baseURL: "https://api.example.com/v1/", apiKey: "k", model: "m",
                                         effort: "high", messages: [ChatMessage(role: "user", content: "hi")])
    eq(req.url?.absoluteString, "https://api.example.com/v1/chat/completions", "url")
    eq(req.value(forHTTPHeaderField: "Authorization"), "Bearer k", "auth header")
    let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String: Any]
    eq(body["reasoning_effort"] as? String, "high", "reasoning_effort")
    eq(body["stream"] as? Bool, true, "stream flag")
    let bare = try ChatClient.makeRequest(baseURL: "https://x/v1", apiKey: nil, model: "m", effort: nil, messages: [])
    let bareBody = try JSONSerialization.jsonObject(with: bare.httpBody!) as! [String: Any]
    check(bareBody["reasoning_effort"] == nil, "no effort -> no reasoning_effort")
    check(bare.value(forHTTPHeaderField: "Authorization") == nil, "no key -> no auth header")
} catch { check(false, "request threw \(error)") }

// MARK: Streaming against a stubbed URLSession

final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var status = 200
    nonisolated(unsafe) static var body = ""
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let resp = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil,
                                   headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

let stubSession: URLSession = {
    let c = URLSessionConfiguration.ephemeral
    c.protocolClasses = [StubProtocol.self]
    return URLSession(configuration: c)
}()

func collect(_ s: AsyncThrowingStream<StreamEvent, Error>) async throws -> [StreamEvent] {
    var out: [StreamEvent] = []
    for try await e in s { out.append(e) }
    return out
}

section("streaming: reasoning then content")
StubProtocol.status = 200
StubProtocol.body = """
data: {"choices":[{"delta":{"reasoning_content":"think"}}]}

data: {"choices":[{"delta":{"content":"Hel"}}]}

data: {"choices":[{"delta":{"content":"lo"}}]}

data: [DONE]

"""
do {
    let events = try await collect(ChatClient.stream(baseURL: "https://x/v1", apiKey: nil, model: "m", effort: nil,
                                                     messages: [ChatMessage(role: "user", content: "hi")],
                                                     session: stubSession))
    eq(events, [.reasoning("think"), .content("Hel"), .content("lo")], "event order")
} catch { check(false, "stream threw \(error)") }

section("streaming: HTTP error carries the server message")
StubProtocol.status = 401
StubProtocol.body = #"{"error":{"message":"Invalid key"}}"#
do {
    _ = try await collect(ChatClient.stream(baseURL: "https://x/v1", apiKey: "bad", model: "m", effort: nil,
                                            messages: [], session: stubSession))
    check(false, "should have thrown")
} catch {
    eq(error.localizedDescription, "Invalid key (HTTP 401)", "error text")
}

section("streaming: in-stream error")
StubProtocol.status = 200
StubProtocol.body = "data: {\"error\":{\"message\":\"overloaded\"}}\n\n"
do {
    _ = try await collect(ChatClient.stream(baseURL: "https://x/v1", apiKey: nil, model: "m", effort: nil,
                                            messages: [], session: stubSession))
    check(false, "should have thrown")
} catch {
    eq(error.localizedDescription, "overloaded", "in-stream error text")
}

// MARK: Store

section("store: import selects the config default, persists, removes")
await MainActor.run {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let defaults = UserDefaults(suiteName: UUID().uuidString)!
    let keys = MemoryKeyStore()
    let store = Store(directory: dir, defaults: defaults, keys: keys)
    do {
        eq(try store.importConfig(fixture), 1, "endpoints imported")
        eq(store.current?.model.id, "glm-5.3-abliterated", "default model selected")
        store.select(variant: store.current?.model.variants.first { $0.id == "high" })
        eq(store.current?.variant?.effort, "high", "variant selected")

        store.setAPIKey("sk-test", for: store.endpoints[0].id)
        eq(store.apiKey(for: store.endpoints[0].id), "sk-test", "key stored")

        // A second Store on the same files sees the same data.
        let again = Store(directory: dir, defaults: defaults, keys: keys)
        eq(again.endpoints.count, 1, "endpoints persisted")
        eq(again.current?.variant?.id, "high", "selection persisted")

        store.remove(store.endpoints[0].id)
        check(store.current == nil, "selection cleared after removal")
    } catch { check(false, "store threw \(error)") }
}

print(failures == 0 ? "\n✓ all \(checks) checks passed" : "\n✗ \(failures) of \(checks) checks failed")
exit(failures == 0 ? 0 : 1)
