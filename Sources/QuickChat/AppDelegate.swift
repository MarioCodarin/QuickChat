import AppKit
import Carbon.HIToolbox
import QuickChatCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()
    private(set) var panels: PanelController!
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        panels = PanelController(store: store)
        installMainMenu()
        installStatusItem()
        hotKey = HotKey(keyCode: kVK_Space, modifiers: optionKey) { [weak self] in
            DispatchQueue.main.async { self?.panels.toggle() }
        }
        // First launch with nothing configured: open the panel so there's something to see.
        if store.endpoints.isEmpty || CommandLine.arguments.contains("--show") { panels.show() }
    }

    // MARK: Status item

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = Self.menuBarIcon()
        button.toolTip = "QuickChat (⌥Space)"
        button.target = self
        button.action = #selector(statusClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Open QuickChat", action: #selector(openPanel), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: "").target = self
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quit QuickChat", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem.menu = menu
            sender.performClick(nil)
            statusItem.menu = nil
        } else {
            panels.toggle()
        }
    }

    @objc private func openPanel() { panels.show() }
    @objc private func openSettings() { panels.show(settings: true) }

    /// A chat bubble holding a prompt chevron and a cursor: the same motif as the app icon.
    private static func menuBarIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let bubble = NSBezierPath(roundedRect: NSRect(x: 2, y: 3.5, width: 14, height: 11), xRadius: 4, yRadius: 4)
            bubble.lineWidth = 1.6
            bubble.stroke()

            let chevron = NSBezierPath()
            chevron.move(to: NSPoint(x: 5.8, y: 11.4))
            chevron.line(to: NSPoint(x: 8.4, y: 9))
            chevron.line(to: NSPoint(x: 5.8, y: 6.6))
            chevron.lineWidth = 1.5
            chevron.lineCapStyle = .round
            chevron.lineJoinStyle = .round
            chevron.stroke()

            NSBezierPath(roundedRect: NSRect(x: 9.8, y: 6.2, width: 3.2, height: 1.7), xRadius: 0.8, yRadius: 0.8).fill()
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: Main menu
    // An accessory app shows no menu bar, but ⌘C/⌘V/⌘A/⌘Z only work in text fields if these items exist.

    private func installMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit QuickChat", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }
}
