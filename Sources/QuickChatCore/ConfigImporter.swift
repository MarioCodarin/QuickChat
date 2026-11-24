import Foundation

public struct ImportedEndpoint {
    public var endpoint: Endpoint
    public var apiKey: String?
}

public struct ImportResult {
    public var endpoints: [ImportedEndpoint]
    /// "providerKey/modelId" from the config's top-level `model`, if present.
    public var defaultModel: String?
    /// Keys of providers the config referenced, so a default can be resolved.
    public var providerKeys: [UUID: String]
}

public enum ImportError: LocalizedError {
    case invalidJSON
    case noProviders

    public var errorDescription: String? {
        switch self {
        case .invalidJSON: return "That doesn't look like valid JSON."
        case .noProviders: return "No provider with a baseURL and at least one model was found."
        }
    }
}

/// Reads the opencode-style config (`provider.<key>.options.baseURL`, `models`, `variants`).
/// Also accepts a pasted fragment (just the `provider` object) and JSON with comments or trailing commas.
public enum ConfigImporter {
    public static func parse(_ text: String) throws -> ImportResult {
        let cleaned = stripJSONC(text)
        guard let data = cleaned.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw ImportError.invalidJSON }

        let providers: [String: Any]
        if let p = root["provider"] as? [String: Any] {
            providers = p
        } else if root.values.contains(where: { isProvider($0) }) {
            providers = root                      // fragment: just the providers
        } else if isProvider(root) {
            providers = ["custom": root]          // fragment: a single provider
        } else {
            throw ImportError.noProviders
        }

        var results: [ImportedEndpoint] = []
        var keys: [UUID: String] = [:]
        for key in providers.keys.sorted() {
            guard let dict = providers[key] as? [String: Any], isProvider(dict),
                  let options = dict["options"] as? [String: Any],
                  let baseURL = options["baseURL"] as? String
            else { continue }

            let name = (dict["name"] as? String) ?? key
            let models = parseModels(dict["models"] as? [String: Any] ?? [:])
            guard !models.isEmpty else { continue }       // nothing to chat with
            var apiKey = options["apiKey"] as? String
            if let k = apiKey, k.hasPrefix("{env:") || k.hasPrefix("{file:") { apiKey = nil }

            let endpoint = Endpoint(name: name, baseURL: baseURL, models: models)
            keys[endpoint.id] = key
            results.append(ImportedEndpoint(endpoint: endpoint, apiKey: apiKey))
        }
        guard !results.isEmpty else { throw ImportError.noProviders }
        return ImportResult(endpoints: results, defaultModel: root["model"] as? String, providerKeys: keys)
    }

    private static func isProvider(_ value: Any) -> Bool {
        guard let d = value as? [String: Any], let o = d["options"] as? [String: Any] else { return false }
        return o["baseURL"] is String
    }

    private static let effortOrder = ["off", "none", "minimal", "low", "medium", "high", "max", "xhigh"]

    private static func parseModels(_ models: [String: Any]) -> [ModelSpec] {
        models.keys.sorted().compactMap { id in
            guard let m = models[id] as? [String: Any] else { return nil }
            var variants: [Variant] = []
            if let vs = m["variants"] as? [String: Any] {
                for (vid, raw) in vs {
                    let v = raw as? [String: Any] ?? [:]
                    if (v["disabled"] as? Bool) == true { continue }
                    variants.append(Variant(id: vid, effort: v["reasoningEffort"] as? String))
                }
                variants.sort { a, b in
                    let ia = effortOrder.firstIndex(of: a.id) ?? 99
                    let ib = effortOrder.firstIndex(of: b.id) ?? 99
                    return ia == ib ? a.id < b.id : ia < ib
                }
            }
            return ModelSpec(id: id, name: m["name"] as? String, variants: variants)
        }
    }

    /// Removes `//` and `/* */` comments, then trailing commas, leaving string contents untouched.
    static func stripJSONC(_ input: String) -> String {
        removeTrailingCommas(removeComments(input))
    }

    private static func removeComments(_ input: String) -> String {
        let chars = Array(input)
        var out: [Character] = []
        var i = 0
        var inString = false
        while i < chars.count {
            let c = chars[i]
            if inString {
                out.append(c)
                if c == "\\", i + 1 < chars.count { out.append(chars[i + 1]); i += 2; continue }
                if c == "\"" { inString = false }
                i += 1
                continue
            }
            if c == "\"" { inString = true; out.append(c); i += 1; continue }
            if c == "/", i + 1 < chars.count, chars[i + 1] == "/" {
                while i < chars.count, chars[i] != "\n" { i += 1 }
                continue
            }
            if c == "/", i + 1 < chars.count, chars[i + 1] == "*" {
                i += 2
                while i + 1 < chars.count, !(chars[i] == "*" && chars[i + 1] == "/") { i += 1 }
                i += 2
                continue
            }
            out.append(c)
            i += 1
        }
        return String(out)
    }

    private static func removeTrailingCommas(_ input: String) -> String {
        let chars = Array(input)
        var out: [Character] = []
        var i = 0
        var inString = false
        while i < chars.count {
            let c = chars[i]
            if inString {
                out.append(c)
                if c == "\\", i + 1 < chars.count { out.append(chars[i + 1]); i += 2; continue }
                if c == "\"" { inString = false }
                i += 1
                continue
            }
            if c == "\"" { inString = true }
            if c == "," {
                var j = i + 1
                while j < chars.count, chars[j].isWhitespace { j += 1 }
                if j < chars.count, chars[j] == "}" || chars[j] == "]" { i += 1; continue }
            }
            out.append(c)
            i += 1
        }
        return String(out)
    }
}
