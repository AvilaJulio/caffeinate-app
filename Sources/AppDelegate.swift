import AppKit

/// Wiring only: restores saved state at launch, keeps UserDefaults in sync
/// with the assertion, and releases the assertion on quit.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Persisted so a launchd relaunch after a crash comes back awake.
    /// Without this, launchd faithfully restarts the app but it returns in the
    /// off state, so the display quietly starts sleeping again and the user
    /// never notices — which is the exact failure this app exists to prevent.
    static let stateKey = "keepAwakeEnabled"

    private let awake = AwakeController()
    private let defaults = UserDefaults.standard
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let controller = StatusItemController(onToggle: { [weak self] in
            self?.toggle()
        })
        statusItem = controller

        if defaults.bool(forKey: Self.stateKey) {
            awake.enable()
        }
        controller.render(isOn: awake.isOn)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Release the assertion but deliberately do NOT touch UserDefaults:
        // the persisted value has to survive quit so the next launch restores
        // it. Writing `false` here would silently break crash recovery.
        awake.disable()
    }

    private func toggle() {
        awake.toggle()
        defaults.set(awake.isOn, forKey: Self.stateKey)
        statusItem?.render(isOn: awake.isOn)
    }
}
