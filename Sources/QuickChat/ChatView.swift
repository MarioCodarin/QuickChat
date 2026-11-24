import AppKit
import SwiftUI
import QuickChatCore

struct RootView: View {
    @ObservedObject var store: Store
    @ObservedObject var chat: ChatModel
    @ObservedObject var ui: PanelState
    var onHeight: (CGFloat) -> Void

    var body: some View {
        Group {
            if ui.showSettings {
                SettingsView(store: store, ui: ui)
            } else {
                ChatView(store: store, chat: chat, ui: ui)
            }
        }
        .frame(width: Theme.width)
        .fixedSize(horizontal: false, vertical: true)
        .readHeight(onHeight)
        .frame(maxHeight: .infinity, alignment: .top)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
                .allowsHitTesting(false)
        )
        .tint(Theme.accent(store.accentID))
        .preferredColorScheme(Theme.colorScheme(store.themeID))
    }
}

struct ChatView: View {
    @ObservedObject var store: Store
    @ObservedObject var chat: ChatModel
    @ObservedObject var ui: PanelState

    @State private var inputHeight: CGFloat = 32
    @State private var answerHeight: CGFloat = 0

    private var accent: Color { Theme.accent(store.accentID) }
    private var canSend: Bool { !ui.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var placeholder: String {
        let name = store.userName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Ask anything" : "Ask anything, \(name)"
    }

    var body: some View {
        VStack(spacing: 0) {
            inputRow
            if !chat.turns.isEmpty {
                Divider().opacity(0.5)
                answers
            }
            Divider().opacity(0.5)
            controls
        }
    }

    // MARK: Input

    private var inputRow: some View {
        HStack(alignment: .top, spacing: 12) {
            // The prompt chevron is this app's signature: it is also in the icon.
            Image(systemName: "chevron.right")
                .font(Typo.body.weight(.medium))
                .foregroundStyle(accent)
                .frame(width: 12, height: 32)

            ZStack(alignment: .topLeading) {
                if ui.input.isEmpty {
                    Text(placeholder)
                        .font(Typo.input)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                        .allowsHitTesting(false)
                }
                InputField(text: $ui.input, height: $inputHeight, accent: accent, onSubmit: submit)
            }
            .frame(height: inputHeight)

            Button(action: chat.isStreaming ? chat.stop : submit) {
                Image(systemName: chat.isStreaming ? "stop.circle.fill" : "arrow.up.circle.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(chat.isStreaming || canSend ? accent : Color.primary.opacity(0.15))
            }
            .buttonStyle(.plain)
            .frame(height: 32)
            .disabled(!chat.isStreaming && !canSend)
            .help(chat.isStreaming ? "Stop" : "Send")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func submit() {
        guard canSend, !chat.isStreaming else { return }
        let text = ui.input
        ui.input = ""
        chat.send(text, store: store)
    }

    // MARK: Answers

    private var answers: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(chat.turns) { turn in
                        TurnView(turn: turn, accent: accent,
                                 streaming: chat.isStreaming && turn.id == chat.turns.last?.id)
                    }
                    // Scroll anchor; the negative inset cancels the stack spacing above it.
                    Color.clear.frame(height: 1).id("bottom").padding(.top, -17)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .readHeight { answerHeight = $0 }
            }
            .frame(height: min(max(answerHeight, 40), 360))
            .onChange(of: chat.turns.last?.answer) { _ in proxy.scrollTo("bottom") }
            .onChange(of: chat.turns.count) { _ in proxy.scrollTo("bottom") }
        }
    }

    // MARK: Controls

    private var controls: some View {
        HStack(spacing: 8) {
            modelMenu
            effortMenu
            Spacer()
            if !chat.turns.isEmpty {
                Button { chat.clear() } label: {
                    ControlLabel { Label("New", systemImage: "plus").labelStyle(.titleAndIcon) }
                }
                .buttonStyle(.plain)
                .help("New chat (⌘N)")
            }
            Button { ui.showSettings = true } label: {
                ControlLabel(width: 28) { Image(systemName: "gearshape") }
            }
            .buttonStyle(.plain)
            .help("Settings (⌘,)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var modelMenu: some View {
        Menu {
            ForEach(store.endpoints) { endpoint in
                Section(endpoint.name) {
                    ForEach(endpoint.models) { model in
                        Button {
                            store.select(endpoint: endpoint, model: model)
                        } label: {
                            if store.selection.endpointID == endpoint.id && store.selection.modelID == model.id {
                                Label(model.name, systemImage: "checkmark")
                            } else {
                                Text(model.name)
                            }
                        }
                    }
                }
            }
        } label: {
            Pill(text: store.current?.model.name ?? "No model")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .tint(Color(nsColor: .secondaryLabelColor))     // menus would otherwise paint their label in the accent
        .fixedSize()
    }

    @ViewBuilder
    private var effortMenu: some View {
        if let current = store.current, !current.model.variants.isEmpty {
            Menu {
                Button { store.select(variant: nil) } label: {
                    if current.variant == nil { Label("Default", systemImage: "checkmark") } else { Text("Default") }
                }
                ForEach(current.model.variants) { v in
                    Button { store.select(variant: v) } label: {
                        if current.variant?.id == v.id { Label(v.id.capitalized, systemImage: "checkmark") }
                        else { Text(v.id.capitalized) }
                    }
                }
            } label: {
                Pill(text: current.variant?.id.capitalized ?? "Default")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .tint(Color(nsColor: .secondaryLabelColor))
            .fixedSize()
        }
    }
}

struct TurnView: View {
    let turn: ChatModel.Turn
    let accent: Color
    let streaming: Bool
    @State private var showReasoning = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(turn.question)
                .font(Typo.ui.weight(.medium))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if !turn.reasoning.isEmpty {
                Button { showReasoning.toggle() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showReasoning ? "chevron.down" : "chevron.right")
                            .font(Typo.meta.weight(.medium))
                        Text(streaming && turn.answer.isEmpty ? "Thinking" : "Thought process")
                            .font(Typo.meta)
                    }
                    .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                if showReasoning {
                    Text(turn.reasoning)
                        .font(Typo.ui)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.leading, 12)
                        .overlay(alignment: .leading) { Rectangle().fill(Color.primary.opacity(0.15)).frame(width: 2) }
                }
            }

            if let error = turn.error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(Typo.ui)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            } else if turn.answer.isEmpty {
                if streaming && turn.reasoning.isEmpty { BlockCursor(color: accent) }
            } else {
                Text(Self.markdown(turn.answer))
                    .font(Typo.body)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !streaming {
                    Button { copy() } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(Typo.meta)
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(turn.answer, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }

    static func markdown(_ s: String) -> AttributedString {
        // Inline-only parsing keeps whitespace intact while streaming; list markers become real bullets.
        let bulleted = s.replacingOccurrences(of: "(?m)^(\\s*)[-*] ", with: "$1• ", options: .regularExpression)
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: bulleted, options: options)) ?? AttributedString(bulleted)
    }
}
