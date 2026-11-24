import Foundation

/// A reasoning-effort option for a model, e.g. `low` / `high` / `max`.
public struct Variant: Codable, Hashable, Identifiable, Sendable {
    public var id: String          // key in the config ("high")
    public var effort: String      // value sent as `reasoning_effort`

    public init(id: String, effort: String? = nil) {
        self.id = id
        self.effort = effort ?? id
    }
}

public struct ModelSpec: Codable, Hashable, Identifiable, Sendable {
    public var id: String          // model id sent to the API
    public var name: String        // display name
    public var variants: [Variant]

    public init(id: String, name: String? = nil, variants: [Variant] = []) {
        self.id = id
        self.name = name ?? id
        self.variants = variants
    }
}

public struct Endpoint: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var baseURL: String
    public var models: [ModelSpec]

    public init(id: UUID = UUID(), name: String, baseURL: String, models: [ModelSpec] = []) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.models = models
    }
}

public struct ChatMessage: Codable, Hashable, Sendable {
    public var role: String        // "system" | "user" | "assistant"
    public var content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}
