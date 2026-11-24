import AppKit
import SwiftUI
import QuickChatCore

struct SettingsView: View {
    @ObservedObject var store: Store
    @ObservedObject var ui: PanelState

    @State private var contentHeight: CGFloat = 300
    @State private var pasted = ""
    @State private var importMessage: (text: String, ok: Bool)?
    @State private var manualName = ""
    @State private var manualURL = ""
    @State private var manualKey = ""
    @State private var manualModels = ""
    @State private var showManual = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    profile
                    endpoints
                    addEndpoint
                    footer
                }
                .padding(24)
                .readHeight { contentHeight = $0 }
            }
            .frame(height: min(max(contentHeight, 80), 460))
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                ui.showSettings = false
                NotificationCenter.default.post(name: .quickChatFocusInput, object: nil)
            } label: {
                ControlLabel(width: 28) { Image(systemName: "chevron.left") }
            }
            .buttonStyle(.plain)
            .disabled(store.endpoints.isEmpty)
            .opacity(store.endpoints.isEmpty ? 0.3 : 1)
            .help("Back (esc)")
            Text("Settings").font(Typo.body.weight(.medium))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var profile: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Profile")
            Field(placeholder: "Your name", text: $store.userName)

            HStack(spacing: 12) {
                ForEach(Theme.presets) { preset in
                    Button { store.accentID = preset.id } label: {
                        Circle().fill(preset.color).frame(width: 20, height: 20)
                            .overlay(Circle()
                                .strokeBorder(Color.primary.opacity(store.accentID == preset.id ? 0.9 : 0), lineWidth: 2)
                                .padding(-4))
                    }
                    .buttonStyle(.plain)
                    .help(preset.name)
                }
                Spacer()
                Segmented(options: [("auto", "Auto"), ("light", "Light"), ("dark", "Dark")],
                          selection: $store.themeID)
                    .onChange(of: store.themeID) { _ in
                        DispatchQueue.main.async { (NSApp.delegate as? AppDelegate)?.panels.applyAppearance() }
                    }
            }
            .padding(.leading, 4)
        }
    }

    private var endpoints: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Endpoints")
            if store.endpoints.isEmpty {
                Text("None yet. Paste a config below to get started")
                    .font(Typo.ui).foregroundStyle(.secondary)
            }
            ForEach(store.endpoints) { endpoint in
                EndpointRow(store: store, endpoint: endpoint)
            }
        }
    }

    private var addEndpoint: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Add endpoint")
            ZStack(alignment: .topLeading) {
                TextEditor(text: $pasted)
                    .font(Typo.mono)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(height: 96)
                    .hoverSurface()
                if pasted.isEmpty {
                    Text("Paste a config (JSON)")
                        .font(Typo.mono)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 13).padding(.vertical, 16)
                        .allowsHitTesting(false)
                }
            }
            HStack(spacing: 12) {
                Button("Import config", action: importPasted)
                    .buttonStyle(PrimaryButton())
                    .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let m = importMessage {
                    Text(m.text).font(Typo.meta).foregroundStyle(m.ok ? Color.secondary : Color.red)
                }
                Spacer()
                Button { withAnimation(.easeOut(duration: 0.15)) { showManual.toggle() } } label: {
                    Text(showManual ? "Hide form" : "Add manually").font(Typo.ui)
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            }

            if showManual {
                VStack(spacing: 8) {
                    Field(placeholder: "Name", text: $manualName)
                    Field(placeholder: "Base URL", text: $manualURL)
                    Field(placeholder: "API key", text: $manualKey, secure: true)
                    Field(placeholder: "Model IDs, separated by commas", text: $manualModels)
                    HStack {
                        Spacer()
                        Button("Add endpoint", action: addManual)
                            .buttonStyle(PrimaryButton())
                            .disabled(manualURL.isEmpty || manualModels.isEmpty)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            KeyHint(keys: "⌥Space", label: "open")
            KeyHint(keys: "⏎", label: "send")
            KeyHint(keys: "⇧⏎", label: "newline")
            KeyHint(keys: "⌘N", label: "new chat")
            KeyHint(keys: "esc", label: "close")
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain).font(Typo.ui).foregroundStyle(.secondary)
        }
    }

    // MARK: Actions

    private func importPasted() {
        do {
            let n = try store.importConfig(pasted)
            pasted = ""
            importMessage = ("Imported \(n) endpoint\(n == 1 ? "" : "s"), check its API key", true)
        } catch {
            importMessage = (error.localizedDescription, false)
        }
    }

    private func addManual() {
        let models = manualModels.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .map { ModelSpec(id: $0) }
        let url = manualURL.trimmingCharacters(in: .whitespaces)
        let name = manualName.trimmingCharacters(in: .whitespaces)
        store.add(Endpoint(name: name.isEmpty ? (URL(string: url)?.host ?? "Custom") : name, baseURL: url, models: models),
                  apiKey: manualKey)
        manualName = ""; manualURL = ""; manualKey = ""; manualModels = ""
        showManual = false
        importMessage = ("Endpoint added", true)
    }
}

struct EndpointRow: View {
    @ObservedObject var store: Store
    let endpoint: Endpoint
    @State private var key = ""
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(endpoint.name).font(Typo.ui.weight(.medium))
                Text("\(endpoint.models.count) model\(endpoint.models.count == 1 ? "" : "s")")
                    .font(Typo.meta).foregroundStyle(.secondary)
                Spacer()
                Button { store.remove(endpoint.id) } label: {
                    ControlLabel(width: 28) { Image(systemName: "trash") }
                }
                .buttonStyle(.plain).help("Remove endpoint")
            }
            Text(endpoint.baseURL)
                .font(Typo.mono).foregroundStyle(.secondary).lineLimit(1)
            Field(placeholder: "API key", text: $key, secure: true)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.primary.opacity(0.10)))
        .onAppear { key = store.apiKey(for: endpoint.id) ?? ""; loaded = true }
        .onChange(of: key) { new in
            // Only write real edits: loading the stored value also fires onChange.
            if loaded, new != (store.apiKey(for: endpoint.id) ?? "") { store.setAPIKey(new, for: endpoint.id) }
        }
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Typo.ui.weight(.medium)).foregroundStyle(.secondary)
    }
}
