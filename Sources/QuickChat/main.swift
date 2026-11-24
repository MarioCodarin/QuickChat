import AppKit

// Menu-bar only: no Dock icon, no app switcher entry (also set via LSUIElement in the bundle).
let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
