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

    private var accent: Color { Theme.accent(store.accentID) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    profile
                    endpoints
                    addEndpoint
                    footer
                }
                .padding(22)
                .readHeight { contentHeight = $0 }
            }
            .frame(height: min(max(contentHeight, 80), 460))
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 10) {
            Button {
                ui.showSettings = false
                NotificationCenter.default.post(name: .quickChatFocusInput, object: nil)
            } label: {
                Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
                    .padding(7).surface(radius: 8)
            }
            .buttonStyle(.plain)
            .disabled(store.endpoints.isEmpty)
            .opacity(store.endpoints.isEmpty ? 0.3 : 1)
            Text("Settings").font(.system(size: 15, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var profile: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle("You")
            TextField("Your name", text: $store.userName)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(.horizontal, 12).padding(.vertical, 9)
                .surface()

            HStack(spacing: 10) {
                ForEach(Theme.presets) { preset in
                    Button { store.accentID = preset.id } label: {
                        Circle().fill(preset.color).frame(width: 20, height: 20)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(store.accentID == preset.id ? 0.9 : 0), lineWidth: 2).padding(-4))
                    }
                    .buttonStyle(.plain)
                    .help(preset.name)
                }
                Spacer()
                Picker("", selection: $store.themeID) {
                    Text("Auto").tag("auto")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
                .onChange(of: store.themeID) { _ in
                    DispatchQueue.main.async { (NSApp.delegate as? AppDelegate)?.panels.applyAppearance() }
                }
            }
            .padding(.leading, 4)
        }
    }

    private var endpoints: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Endpoints")
            if store.endpoints.isEmpty {
                Text("None yet. Paste a config below to get started.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            ForEach(store.endpoints) { endpoint in
                EndpointRow(store: store, endpoint: endpoint)
            }
        }
    }

    private var addEndpoint: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Add")
            ZStack(alignment: .topLeading) {
                TextEditor(text: $pasted)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 96)
                    .surface()
                if pasted.isEmpty {
                    Text("Paste an opencode / OpenAI-compatible config (JSON)…")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12).padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            HStack {
                Button("Import config", action: importPasted)
                    .buttonStyle(AccentButton(color: accent))
                    .disabled(pasted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let m = importMessage {
                    Text(m.text).font(.system(size: 12)).foregroundStyle(m.ok ? Color.secondary : Color.red)
                }
                Spacer()
                Button { withAnimation(.snappy) { showManual.toggle() } } label: {
                    Text(showManual ? "Hide manual form" : "Add manually").font(.system(size: 12))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            }

            if showManual {
                VStack(spacing: 8) {
                    Field("Name (e.g. OpenAI)", text: $manualName)
                    Field("Base URL (https://api.openai.com/v1)", text: $manualURL)
                    SecureField("API key", text: $manualKey)
                        .textFieldStyle(.plain).font(.system(size: 13))
                        .padding(.horizontal, 12).padding(.vertical, 8).surface()
                    Field("Model IDs, comma separated (gpt-5, gpt-5-mini)", text: $manualModels)
                    HStack {
                        Spacer()
                        Button("Add endpoint", action: addManual)
                            .buttonStyle(AccentButton(color: accent))
                            .disabled(manualURL.isEmpty || manualModels.isEmpty)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Text("⌥Space to open · ⏎ send · ⇧⏎ newline · ⌘N new chat · Esc close")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
            Spacer()
            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    // MARK: Actions

    private func importPasted() {
        do {
            let n = try store.importConfig(pasted)
            pasted = ""
            importMessage = ("Imported \(n) endpoint\(n == 1 ? "" : "s"). Make sure each has its API key.", true)
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
        importMessage = ("Endpoint added.", true)
    }
}

struct EndpointRow: View {
    @ObservedObject var store: Store
    let endpoint: Endpoint
    @State private var key = ""
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(endpoint.name).font(.system(size: 14, weight: .semibold))
                Text("\(endpoint.models.count) model\(endpoint.models.count == 1 ? "" : "s")")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Button { store.remove(endpoint.id) } label: {
                    Image(systemName: "trash").font(.system(size: 12))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Remove endpoint")
            }
            Text(endpoint.baseURL)
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
            SecureField("API key", text: $key)
                .textFieldStyle(.plain).font(.system(size: 13))
                .padding(.horizontal, 12).padding(.vertical, 8).surface()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.10)))
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
        Text(text).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
    }
}

struct Field: View {
    let placeholder: String
    @Binding var text: String
    init(_ placeholder: String, text: Binding<String>) { self.placeholder = placeholder; _text = text }
    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain).font(.system(size: 13))
            .padding(.horizontal, 12).padding(.vertical, 8).surface()
    }
}

struct AccentButton: ButtonStyle {
    let color: Color
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Capsule().fill(color.opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.3)))
    }
}
