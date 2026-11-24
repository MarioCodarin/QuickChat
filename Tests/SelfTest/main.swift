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

// MARK: Regression checks from code review

section("review: SSE edge cases")
eq(SSE.parse(line: #"data:{"choices":[{"delta":{"content":"x"}}]}"#), .events([.content("x")]), "data: without a space")
eq(SSE.parse(line: #"data: {"choices":[{"delta":{"reasoning_content":"","reasoning":"r"}}]}"#), .events([.reasoning("r")]),
   "empty reasoning_content falls back to reasoning")
eq(SSE.parse(line: #"data: {"choices":[],"usage":{"total_tokens":3}}"#), .ignore, "usage-only chunk")
eq(SSE.parse(line: #"data: {"choices":[{"delta":{"content":null}}]}"#), .ignore, "null content")
eq(SSE.parse(line: #"{"choices":[{"message":{"content":"plain"}}]}"#), .events([.content("plain")]), "non-streamed JSON line")

section("review: servers that don't stream")
StubProtocol.status = 200
StubProtocol.body = #"{"choices":[{"message":{"role":"assistant","content":"all at once"}}]}"#
do {
    let events = try await collect(ChatClient.stream(baseURL: "https://x/v1", apiKey: nil, model: "m", effort: nil,
                                                     messages: [], session: stubSession))
    eq(events, [.content("all at once")], "plain JSON completion is shown")
} catch { check(false, "plain JSON threw \(error)") }

StubProtocol.body = ""
do {
    _ = try await collect(ChatClient.stream(baseURL: "https://x/v1", apiKey: nil, model: "m", effort: nil,
                                            messages: [], session: stubSession))
    check(false, "empty 200 should throw")
} catch { eq(error.localizedDescription, "The server returned an empty response.", "empty 200 is an error") }

StubProtocol.body = #"{"error":{"message":"quota exceeded"}}"#
do {
    _ = try await collect(ChatClient.stream(baseURL: "https://x/v1", apiKey: nil, model: "m", effort: nil,
                                            messages: [], session: stubSession))
    check(false, "error body with 200 should throw")
} catch { eq(error.localizedDescription, "quota exceeded", "error JSON inside a 200") }

section("review: firewall page is not reported as a bad key")
StubProtocol.status = 403
StubProtocol.body = "<!DOCTYPE html><html><head><title>Attention Required! | Cloudflare</title></head><body>Sorry, you have been blocked</body></html>"
do {
    _ = try await collect(ChatClient.stream(baseURL: "https://x/v1", apiKey: "k", model: "m", effort: nil,
                                            messages: [], session: stubSession))
    check(false, "403 should throw")
} catch {
    check(error.localizedDescription.contains("Cloudflare"), "message names the firewall: \(error.localizedDescription)")
    check(!error.localizedDescription.contains("API key"), "does not blame the key")
}

section("review: importer edge cases")
check((try? ConfigImporter.parse(#"{"provider":{"p":{"options":{"baseURL":"https://x/v1"}}}}"#)) == nil,
      "provider without models is not imported")
do {
    let r = try ConfigImporter.parse("""
    {"p": {"options": {"baseURL": "https://x/v1"}, "models": {"a": {},  // note
      }}}
    """)
    eq(r.endpoints.first?.endpoint.models.first?.id, "a", "trailing comma followed by a comment")
} catch { check(false, "comma+comment threw \(error)") }
do {
    let r = try ConfigImporter.parse(#"{"p":{"options":{"baseURL":"https://x/v1"},"models":{"m":{"name":"has // and /* in it"}}}}"#)
    eq(r.endpoints.first?.endpoint.models.first?.name, "has // and /* in it", "comment markers inside strings survive")
} catch { check(false, "string markers threw \(error)") }

section("review: store dedupe and key trimming")
await MainActor.run {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let keys = MemoryKeyStore()
    let store = Store(directory: dir, defaults: UserDefaults(suiteName: UUID().uuidString)!, keys: keys)
    do {
        _ = try store.importConfig(fixture)
        let id = store.endpoints[0].id
        store.setAPIKey("  sk-abc\n", for: id)
        eq(store.apiKey(for: id), "sk-abc", "key is trimmed")

        _ = try store.importConfig(fixture)       // same config again
        eq(store.endpoints.count, 1, "re-import does not duplicate")
        eq(store.endpoints[0].id, id, "re-import keeps the endpoint id")
        eq(store.apiKey(for: id), "sk-abc", "re-import keeps the API key")
        eq(store.current?.endpoint.id, id, "selection still points at the endpoint")
    } catch { check(false, "store review checks threw \(error)") }
}

// MARK: Live endpoint (optional)
// Runs only when REFUSELESS_API_KEY is set, e.g.  REFUSELESS_API_KEY=... swift run selftest
// The key is read from the environment and never stored.

if let liveKey = ProcessInfo.processInfo.environment["REFUSELESS_API_KEY"], !liveKey.isEmpty {
    section("live: Refuseless streaming through ChatClient")
    do {
        let endpoint = try ConfigImporter.parse(fixture).endpoints[0].endpoint
        var content = "", reasoning = ""
        for try await event in ChatClient.stream(baseURL: endpoint.baseURL, apiKey: liveKey,
                                                 model: "glm-5.3-abliterated", effort: "low",
                                                 messages: [ChatMessage(role: "user", content: "Hello")]) {
            switch event {
            case .content(let c): content += c
            case .reasoning(let r): reasoning += r
            }
        }
        print("  reasoning: \(reasoning.count) chars, answer: \"\(content.prefix(80))\"")
        check(!content.isEmpty, "live answer is not empty")
    } catch { check(false, "live stream threw \(error.localizedDescription)") }

    section("live: bad key surfaces a readable error")
    do {
        for try await _ in ChatClient.stream(baseURL: "https://api.refuseless.com/v1", apiKey: "abl_invalid",
                                             model: "glm-5.3-abliterated", effort: nil,
                                             messages: [ChatMessage(role: "user", content: "Hello")]) {}
        check(false, "bad key should have thrown")
    } catch { print("  error shown to user: \(error.localizedDescription)"); check(true, "") }
} else {
    print("• live: skipped (set REFUSELESS_API_KEY to run)")
}

print(failures == 0 ? "\n✓ all \(checks) checks passed" : "\n✗ \(failures) of \(checks) checks failed")
exit(failures == 0 ? 0 : 1)
