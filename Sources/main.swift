import AppKit

let app = NSApplication.shared
// Menu bar only: no Dock icon, no app switcher entry, no main window.
// Info.plist's LSUIElement covers bundle launches; this covers running the
// binary directly, as launchd does.
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate
app.run()
