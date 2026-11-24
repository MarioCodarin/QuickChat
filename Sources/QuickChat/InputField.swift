import AppKit
import SwiftUI

/// Multi-line input where ⏎ sends and ⇧⏎ / ⌥⏎ inserts a newline.
/// (SwiftUI's TextField can't tell those apart reliably on macOS, so this wraps NSTextView.)
struct InputField: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    var accent: Color
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.borderType = .noBorder
        scroll.postsFrameChangedNotifications = true

        let tv = NSTextView()
        tv.delegate = context.coordinator
        tv.drawsBackground = false
        tv.isRichText = false
        tv.allowsUndo = true
        tv.font = .systemFont(ofSize: 20, weight: .regular)
        tv.textColor = .labelColor
        tv.textContainerInset = NSSize(width: 0, height: 4)
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = true
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        scroll.documentView = tv

        let c = context.coordinator
        c.textView = tv
        c.observers = [
            NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: scroll,
                                                   queue: .main) { [weak c] _ in c?.recomputeHeight() },
            NotificationCenter.default.addObserver(forName: .quickChatFocusInput, object: nil,
                                                   queue: .main) { [weak c] _ in c?.focus() },
        ]
        DispatchQueue.main.async { c.focus() }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.parent = self
        guard let tv = c.textView else { return }
        if tv.string != text {
            tv.string = text
            if text.isEmpty { tv.undoManager?.removeAllActions() }   // stale undo ranges after a submit
            c.recomputeHeight()
        }
        tv.insertionPointColor = NSColor(accent)
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: Coordinator) {
        coordinator.observers.forEach(NotificationCenter.default.removeObserver)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InputField
        weak var textView: NSTextView?
        var observers: [NSObjectProtocol] = []

        init(_ parent: InputField) { self.parent = parent }

        func focus() { if let tv = textView { tv.window?.makeFirstResponder(tv) } }

        func textDidChange(_ notification: Notification) {
            guard let tv = textView else { return }
            parent.text = tv.string
            recomputeHeight()
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            let flags = NSEvent.modifierFlags
            if flags.contains(.shift) || flags.contains(.option) {
                textView.insertNewlineIgnoringFieldEditor(nil)
            } else {
                parent.onSubmit()
            }
            return true
        }

        func recomputeHeight() {
            guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
            lm.ensureLayout(for: tc)
            let h = ceil(lm.usedRect(for: tc).height + tv.textContainerInset.height * 2)
            let clamped = min(max(h, 32), 152)
            if abs(parent.height - clamped) > 0.5 {
                DispatchQueue.main.async { self.parent.height = clamped }
            }
        }
    }
}
