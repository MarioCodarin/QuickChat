import Combine
import Foundation

public struct Selection: Codable, Equatable, Sendable {
    public var endpointID: UUID?
    public var modelID: String?
    public var variantID: String?   // nil = provider default (no reasoning_effort sent)
    public init(endpointID: UUID? = nil, modelID: String? = nil, variantID: String? = nil) {
        self.endpointID = endpointID
        self.modelID = modelID
        self.variantID = variantID
    }
}

public struct CurrentModel {
    public var endpoint: Endpoint
    public var model: ModelSpec
    public var variant: Variant?
}

/// Endpoints (JSON on disk), API keys (Keychain) and personalization (UserDefaults).
@MainActor
public final class Store: ObservableObject {
    @Published public private(set) var endpoints: [Endpoint] = []
    @Published public var selection = Selection() { didSet { saveSelection() } }

    @Published public var userName: String { didSet { defaults.set(userName, forKey: "userName") } }
    @Published public var accentID: String { didSet { defaults.set(accentID, forKey: "accent") } }
    @Published public var themeID: String { didSet { defaults.set(themeID, forKey: "theme") } }

    private let fileURL: URL
    private let defaults: UserDefaults
    private let keys: KeyStoring

    public init(directory: URL? = nil, defaults: UserDefaults = .standard, keys: KeyStoring = SystemKeychain()) {
        let dir = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QuickChat", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent("endpoints.json")
        self.defaults = defaults
        self.keys = keys

        // Personalization defaults: first name from the macOS account, ember accent, follow the system theme.
        let systemFirstName = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        self.userName = defaults.string(forKey: "userName") ?? systemFirstName
        self.accentID = defaults.string(forKey: "accent") ?? "ember"
        self.themeID = defaults.string(forKey: "theme") ?? "auto"

        if let data = try? Data(contentsOf: fileURL),
           let list = try? JSONDecoder().decode([Endpoint].self, from: data) {
            endpoints = list
        }
        if let data = defaults.data(forKey: "selection"),
           let sel = try? JSONDecoder().decode(Selection.self, from: data) {
            selection = sel
        }
        normalizeSelection()
    }

    // MARK: Endpoints

    public func add(_ endpoint: Endpoint, apiKey: String?) {
        endpoints.append(endpoint)
        keys.setKey(apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), for: endpoint.id.uuidString)
        saveEndpoints()
        if current == nil, let m = endpoint.models.first {
            selection = Selection(endpointID: endpoint.id, modelID: m.id, variantID: nil)
        }
    }

    public func remove(_ id: UUID) {
        endpoints.removeAll { $0.id == id }
        keys.setKey(nil, for: id.uuidString)
        saveEndpoints()
        normalizeSelection()
    }

    /// Imports an opencode-style config. Importing the same provider again (same name and base URL)
    /// refreshes its models in place and keeps its id and API key. Returns how many endpoints were processed.
    @discardableResult
    public func importConfig(_ text: String) throws -> Int {
        let result = try ConfigImporter.parse(text)

        var resolvedID: [UUID: UUID] = [:]      // imported id -> id actually in the store
        for item in result.endpoints {
            let imported = item.endpoint
            if let i = endpoints.firstIndex(where: { $0.baseURL == imported.baseURL && $0.name == imported.name }) {
                endpoints[i].models = imported.models
                resolvedID[imported.id] = endpoints[i].id
                if let key = item.apiKey { setAPIKey(key, for: endpoints[i].id) }
                saveEndpoints()
            } else {
                add(imported, apiKey: item.apiKey)
                resolvedID[imported.id] = imported.id
            }
        }
        normalizeSelection()                    // a refreshed model list may have dropped the selected model

        // Honour the config's default `model` ("providerKey/modelId").
        if let def = result.defaultModel, let slash = def.firstIndex(of: "/") {
            let providerKey = String(def[..<slash]), modelID = String(def[def.index(after: slash)...])
            if let item = result.endpoints.first(where: { result.providerKeys[$0.endpoint.id] == providerKey }),
               let id = resolvedID[item.endpoint.id], item.endpoint.models.contains(where: { $0.id == modelID }) {
                selection = Selection(endpointID: id, modelID: modelID, variantID: nil)
            }
        }
        return result.endpoints.count
    }

    public func apiKey(for id: UUID) -> String? { keys.key(for: id.uuidString) }
    public func setAPIKey(_ value: String?, for id: UUID) {
        keys.setKey(value?.trimmingCharacters(in: .whitespacesAndNewlines), for: id.uuidString)
    }

    // MARK: Selection

    public var current: CurrentModel? {
        guard let e = endpoints.first(where: { $0.id == selection.endpointID }),
              let m = e.models.first(where: { $0.id == selection.modelID }) else { return nil }
        return CurrentModel(endpoint: e, model: m, variant: m.variants.first { $0.id == selection.variantID })
    }

    public func select(endpoint: Endpoint, model: ModelSpec) {
        // Keep the effort choice when the new model supports it too.
        let keep = model.variants.contains { $0.id == selection.variantID } ? selection.variantID : nil
        selection = Selection(endpointID: endpoint.id, modelID: model.id, variantID: keep)
    }

    public func select(variant: Variant?) { selection.variantID = variant?.id }

    private func normalizeSelection() {
        if current == nil {
            // Prefer another model on the endpoint that was selected, then the first usable endpoint.
            let same = endpoints.first { $0.id == selection.endpointID && !$0.models.isEmpty }
            if let e = same ?? endpoints.first(where: { !$0.models.isEmpty }), let m = e.models.first {
                selection = Selection(endpointID: e.id, modelID: m.id, variantID: nil)
            } else {
                selection = Selection()
            }
        }
    }

    // MARK: Persistence

    private func saveEndpoints() {
        if let data = try? JSONEncoder().encode(endpoints) { try? data.write(to: fileURL, options: .atomic) }
    }

    private func saveSelection() {
        if let data = try? JSONEncoder().encode(selection) { defaults.set(data, forKey: "selection") }
    }
}
