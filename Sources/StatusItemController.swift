import AppKit

/// Owns the menu bar item: its icon, its click routing, and its menu.
/// Knows nothing about IOKit or persistence — it renders a bool and reports
/// clicks back through a closure.
final class StatusItemController {
    /// Pure, so it can be tested without a window server.
    static func symbolName(isOn: Bool) -> String {
        isOn ? "cup.and.saucer.fill" : "cup.and.saucer"
    }

    static func stateTitle(isOn: Bool) -> String {
        isOn ? "Keeping display awake" : "Display sleeps normally"
    }

    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private let stateItem: NSMenuItem
    private let onToggle: () -> Void

    init(onToggle: @escaping () -> Void) {
        self.onToggle = onToggle
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        let stateItem = NSMenuItem(title: Self.stateTitle(isOn: false),
                                   action: nil,
                                   keyEquivalent: "")
        stateItem.isEnabled = false
        self.stateItem = stateItem

        let menu = NSMenu()
        menu.addItem(stateItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Caffeinate",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        self.menu = menu

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            // NSButton only fires on left mouse up by default; opt in to right
            // clicks so one action method can route both.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        render(isOn: false)
    }

    /// Updates the icon and the menu's state line to match `isOn`.
    func render(isOn: Bool) {
        stateItem.title = Self.stateTitle(isOn: isOn)
        guard let button = statusItem.button else { return }
        if let image = NSImage(systemSymbolName: Self.symbolName(isOn: isOn),
                               accessibilityDescription: Self.stateTitle(isOn: isOn)) {
            image.isTemplate = true   // tracks light/dark menu bars
            button.image = image
            button.title = ""
        } else {
            // Never ship an invisible status item: if the symbol is missing,
            // fall back to text rather than rendering nothing.
            button.image = nil
            button.title = isOn ? "☕" : "○"
        }
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp
            || (event?.modifierFlags.contains(.control) ?? false)

        if wantsMenu {
            // A status item shows its menu instead of sending its action when
            // `menu` is set, so attach it only for the duration of this click.
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            onToggle()
        }
    }
}
