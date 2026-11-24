import SwiftUI

/// Four text sizes, two weights (regular, medium). Nothing else.
enum Typo {
    static let meta = Font.system(size: 11)
    static let ui = Font.system(size: 13)
    static let body = Font.system(size: 15)
    static let input = Font.system(size: 20)
    static let mono = Font.system(size: 11, design: .monospaced)
}

/// A quiet neutral surface that steps up slightly under the pointer.
struct HoverSurface: ViewModifier {
    var radius: CGFloat = 8
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.primary.opacity(hovering ? 0.12 : 0.07)))
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

extension View {
    func hoverSurface(radius: CGFloat = 8) -> some View { modifier(HoverSurface(radius: radius)) }
}

/// Fixed-size control, so pills, the gear and the back button share one height.
struct ControlLabel<Content: View>: View {
    var width: CGFloat? = nil
    @ViewBuilder var content: Content

    var body: some View {
        content
            .font(Typo.ui.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, width == nil ? 12 : 0)
            .frame(width: width, height: 28)
            .hoverSurface()
    }
}

/// Text-only pill used by the model and effort menus.
struct Pill: View {
    let text: String
    var body: some View {
        ControlLabel { Text(text).lineLimit(1) }
    }
}

/// Neutral segmented control: the selected segment is one surface step up, not an accent fill.
struct Segmented<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let selected = options[i].value == selection
                Button { selection = options[i].value } label: {
                    Text(options[i].label)
                        .font(Typo.ui.weight(selected ? .medium : .regular))
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .padding(.horizontal, 12)
                        .frame(height: 24)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(selected ? 0.14 : 0)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.07)))
    }
}

/// Primary action: inverted neutral, with the accent kept for the one thing that is selected or in flight.
struct PrimaryButton: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typo.ui.weight(.medium))
            .foregroundStyle(enabled ? (scheme == .dark ? Color.black : Color.white) : Color.secondary.opacity(0.7))
            .padding(.horizontal, 16)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(enabled ? Color.primary.opacity(configuration.isPressed ? 0.75 : 0.92) : Color.primary.opacity(0.07)))
    }
}

struct Keycap: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Typo.meta.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .frame(minWidth: 20, minHeight: 20)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary.opacity(0.07)))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).strokeBorder(Color.primary.opacity(0.10)))
    }
}

struct KeyHint: View {
    let keys: String
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            Keycap(text: keys)
            Text(label).font(Typo.meta).foregroundStyle(.tertiary)
        }
    }
}

/// The block cursor from the app icon, used as the "waiting for the model" indicator.
struct BlockCursor: View {
    let color: Color
    @State private var lit = true
    private let timer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(color)
            .frame(width: 10, height: 16)
            .opacity(lit ? 1 : 0.2)
            .onReceive(timer) { _ in lit.toggle() }
            .accessibilityLabel("Waiting for a response")
    }
}

/// Text field on a neutral surface.
struct Field: View {
    let placeholder: String
    @Binding var text: String
    var secure = false

    var body: some View {
        Group {
            if secure { SecureField(placeholder, text: $text) } else { TextField(placeholder, text: $text) }
        }
        .textFieldStyle(.plain)
        .font(Typo.ui)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .hoverSurface()
    }
}
