import AppKit
import SwiftUI

struct AccentPreset: Identifiable {
    let id: String
    let name: String
    let color: Color
}

enum Theme {
    static let radius: CGFloat = 22
    static let width: CGFloat = 640

    static let presets: [AccentPreset] = [
        AccentPreset(id: "ember", name: "Ember", color: Color(red: 1.00, green: 0.42, blue: 0.24)),
        AccentPreset(id: "sky", name: "Sky", color: Color(red: 0.30, green: 0.60, blue: 1.00)),
        AccentPreset(id: "mint", name: "Mint", color: Color(red: 0.18, green: 0.83, blue: 0.63)),
        AccentPreset(id: "violet", name: "Violet", color: Color(red: 0.61, green: 0.48, blue: 1.00)),
        AccentPreset(id: "rose", name: "Rose", color: Color(red: 1.00, green: 0.36, blue: 0.54)),
        AccentPreset(id: "graphite", name: "Graphite", color: Color(red: 0.56, green: 0.56, blue: 0.58)),
    ]

    static func accent(_ id: String) -> Color {
        (presets.first { $0.id == id } ?? presets[0]).color
    }

    static func colorScheme(_ id: String) -> ColorScheme? {
        switch id {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    static func appearance(_ id: String) -> NSAppearance? {
        switch id {
        case "light": return NSAppearance(named: .aqua)
        case "dark": return NSAppearance(named: .darkAqua)
        default: return nil
        }
    }
}

extension Notification.Name {
    static let quickChatFocusInput = Notification.Name("quickChatFocusInput")
}

/// Measures a view's height so the panel can follow its content.
struct HeightKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

extension View {
    func readHeight(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        background(GeometryReader { Color.clear.preference(key: HeightKey.self, value: $0.size.height) })
            .onPreferenceChange(HeightKey.self, perform: onChange)
    }
}

/// A quiet rounded surface used for fields and pills.
struct Surface: ViewModifier {
    var radius: CGFloat = 10
    func body(content: Content) -> some View {
        content.background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.primary.opacity(0.07)))
    }
}

extension View {
    func surface(radius: CGFloat = 10) -> some View { modifier(Surface(radius: radius)) }
}
