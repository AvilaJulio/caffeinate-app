import Foundation
import IOKit.pwr_mgt

/// Owns the single IOKit power assertion that keeps the display awake.
///
/// This is what `caffeinate -d` does internally. The app takes the assertion
/// itself rather than spawning `caffeinate` because an assertion is owned by
/// the process that created it: the kernel releases it when that process dies
/// by any means, including SIGKILL and panic. A spawned child could be
/// orphaned and leave the Mac permanently awake with no UI left to stop it.
final class AwakeController {
    private static let reason = "Caffeinate is keeping the display awake" as CFString

    private var assertionID: IOPMAssertionID?

    var isOn: Bool { assertionID != nil }

    /// Takes the assertion. No-op if already held. Returns false if the
    /// kernel refused, in which case the controller stays off.
    @discardableResult
    func enable() -> Bool {
        if assertionID != nil { return true }
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            Self.reason,
            &id)
        guard result == kIOReturnSuccess else { return false }
        assertionID = id
        return true
    }

    /// Releases the assertion. No-op if not held.
    func disable() {
        guard let id = assertionID else { return }
        IOPMAssertionRelease(id)
        assertionID = nil
    }

    func toggle() {
        if isOn { disable() } else { enable() }
    }
}
