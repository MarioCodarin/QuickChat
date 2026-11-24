import AppKit
import SwiftUI
import QuickChatCore

/// A borderless, non-activating panel: it takes keyboard focus for typing without
/// pulling QuickChat to the front or stealing focus from the app you were in.
final class FloatingPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Theme.width, height: 120),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// UI state shared between the controller and the SwiftUI views.
@MainActor
final class PanelState: ObservableObject {
    @Published var showSettings = false
    /// Lives here (not in ChatView) so a draft survives a trip to settings and back.
    @Published var input = ""
}

@MainActor
final class PanelController: NSObject {
    let panel = FloatingPanel()
    let store: Store
    let chat = ChatModel()
    let ui = PanelState()

    private var anchorTop: CGFloat = 0
    private var keyMonitor: Any?
    private var contentHeight: CGFloat = 120
    private var maxHeight: CGFloat = 700
    private var resizeScheduled = false

    init(store: Store) {
        self.store = store
        super.init()

        let visual = NSVisualEffectView()
        visual.material = .hudWindow
        visual.blendingMode = .behindWindow
        visual.state = .active
        visual.maskImage = Self.roundedMask(radius: Theme.radius)

        let root = RootView(store: store, chat: chat, ui: ui) { [weak self] h in self?.contentHeightChanged(h) }
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []          // the panel follows the content, not the other way round
        hosting.frame = visual.bounds
        hosting.autoresizingMask = [.width, .height]
        visual.addSubview(hosting)
        panel.contentView = visual

        applyAppearance()
        NotificationCenter.default.addObserver(self, selector: #selector(panelLostKey),
                                               name: NSWindow.didResignKeyNotification, object: panel)
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() { isVisible ? hide() : show() }

    func show(settings: Bool = false) {
        // Already open (e.g. "Open QuickChat" from the menu): just take focus, don't snap back or re-fade.
        if panel.isVisible {
            if settings { ui.showSettings = true }
            panel.makeKey()
            NotificationCenter.default.post(name: .quickChatFocusInput, object: nil)
            return
        }
        ui.showSettings = settings || store.endpoints.isEmpty
        applyAppearance()
        position()
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.12; panel.animator().alphaValue = 1 }
        NotificationCenter.default.post(name: .quickChatFocusInput, object: nil)
        installKeyMonitor()
    }

    func hide() {
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    func applyAppearance() { panel.appearance = Theme.appearance(store.themeID) }

    // MARK: Layout

    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = screen.visibleFrame
        anchorTop = vf.maxY - vf.height * 0.2
        maxHeight = max(200, anchorTop - vf.minY - 20)      // never run off the bottom of a small display
        let size = NSSize(width: Theme.width, height: contentHeight)
        panel.setFrame(NSRect(x: vf.midX - size.width / 2, y: anchorTop - size.height,
                              width: size.width, height: size.height), display: true)
    }

    private func contentHeightChanged(_ h: CGFloat) {
        guard h > 1 else { return }
        contentHeight = min(h, maxHeight)
        // Deferred (we're inside SwiftUI layout) and coalesced: many tokens in one turn cause one window resize.
        guard !resizeScheduled else { return }
        resizeScheduled = true
        DispatchQueue.main.async { [self] in
            resizeScheduled = false
            guard panel.isVisible, abs(panel.frame.height - contentHeight) > 0.5 else { return }
            var frame = panel.frame
            let top = frame.maxY                          // keep the top edge fixed, grow downwards
            frame.size.height = contentHeight
            frame.origin.y = top - contentHeight
            panel.setFrame(frame, display: true)
            panel.invalidateShadow()
        }
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    // MARK: Dismissal and shortcuts

    @objc private func panelLostKey() {
        // A menu popping open can briefly resign key; only dismiss if we really lost focus.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [self] in
            if panel.isVisible && !panel.isKeyWindow && NSApp.keyWindow == nil { hide() }
        }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            let cmd = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
            switch (event.keyCode, cmd) {
            case (53, _):                                  // Esc
                // While an input method is composing, Esc belongs to it (cancel the marked text).
                if (panel.firstResponder as? NSTextView)?.hasMarkedText() == true { return event }
                if ui.showSettings, !store.endpoints.isEmpty { ui.showSettings = false } else { hide() }
                return nil
            case (45, true):                               // ⌘N
                chat.clear(); ui.showSettings = false
                NotificationCenter.default.post(name: .quickChatFocusInput, object: nil)
                return nil
            case (43, true):                               // ⌘,
                ui.showSettings.toggle()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
