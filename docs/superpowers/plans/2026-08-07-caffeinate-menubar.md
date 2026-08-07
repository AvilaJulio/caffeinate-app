# Caffeinate Menu Bar App Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS menu bar app with a coffee cup icon that toggles keep-display-awake, survives its own crashes and reboots, and can never strand the Mac in an awake state.

**Architecture:** The app holds an IOKit `PreventUserIdleDisplaySleep` power assertion directly rather than spawning `/usr/bin/caffeinate`, so the kernel releases it automatically when the process dies. A user LaunchAgent with `RunAtLoad` and `KeepAlive { SuccessfulExit: false }` restarts it after a crash or reboot but respects a deliberate Quit. On/off state persists in `UserDefaults` so a post-crash relaunch comes back awake instead of silently letting the display sleep.

**Tech Stack:** Swift 6 / AppKit / IOKit.pwr_mgt, compiled with `swiftc` directly. No SwiftPM, no Xcode project, no third-party dependencies. Tests are a hand-rolled runner binary — there is no XCTest harness without a package.

## Global Constraints

- Bundle identifier: `dev.julio.caffeinate` (used verbatim as the LaunchAgent `Label` and in the service target `gui/$(id -u)/dev.julio.caffeinate`).
- App name: `Caffeinate`. Bundle: `Caffeinate.app`. Executable: `Caffeinate`.
- Assertion type: `kIOPMAssertionTypePreventUserIdleDisplaySleep` only. Do not add `PreventUserIdleSystemSleep` or `PreventSystemSleep`.
- LaunchAgent `KeepAlive` MUST be the dict `{ SuccessfulExit: false }`, never the boolean `true`. Boolean `true` relaunches after a deliberate Quit and makes Quit look broken.
- `applicationWillTerminate` MUST NOT write to `UserDefaults`. It releases the assertion only; the persisted value must survive quit so the next launch restores it.
- SF Symbols: `cup.and.saucer` (off) and `cup.and.saucer.fill` (on), always with `isTemplate = true`.
- `Info.plist` sets `LSUIElement = true` AND `main.swift` calls `setActivationPolicy(.accessory)`. Both, not either.
- Build output goes to `build/`, which is gitignored. Never commit `build/`.
- All shell scripts start with `#!/usr/bin/env bash` and `set -euo pipefail`.

---

## File Structure

| File | Responsibility |
|---|---|
| `Sources/AwakeController.swift` | The only code that touches IOKit. Owns one assertion ID. No UI, no persistence. |
| `Sources/StatusItemController.swift` | The only code that touches `NSStatusItem`. Icon, click routing, menu. No IOKit, no persistence. |
| `Sources/AppDelegate.swift` | Wiring: restore state at launch, sync `UserDefaults` on toggle, release on terminate. |
| `Sources/main.swift` | `NSApplication` bootstrap and activation policy. |
| `Resources/Info.plist` | Bundle metadata, `LSUIElement`. |
| `Tests/TestSupport.swift` | `check()` assertion helper and the `pmset` probe. |
| `Tests/main.swift` | Test runner entry point. Exits non-zero on any failure. |
| `test.sh` | Compiles sources + tests into a test binary and runs it. |
| `build.sh` | `build` \| `install` \| `uninstall`. |
| `.gitignore` | Ignores `build/`. |

`Sources/main.swift` and `Tests/main.swift` both contain top-level code. This is fine because they are compiled into two separate binaries and never linked together. `test.sh` deliberately omits `Sources/main.swift`.

---

### Task 1: AwakeController and the test harness

The assertion is the whole product; everything else is a button that calls it. This task also establishes the test harness, because this is the first task that needs one.

**Files:**
- Create: `.gitignore`
- Create: `Sources/AwakeController.swift`
- Create: `Tests/TestSupport.swift`
- Create: `Tests/main.swift`
- Create: `test.sh`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `final class AwakeController` with `init()`, `var isOn: Bool { get }`, `@discardableResult func enable() -> Bool`, `func disable()`, `func toggle()`.
  - `func check(_ condition: Bool, _ message: String)` — records a failure and prints; does not throw or exit.
  - `var failureCount: Int` — global, read by `Tests/main.swift` to set the exit code.
  - `func processHoldsDisplayAssertion() -> Bool` — true when *this* process holds a `PreventUserIdleDisplaySleep` assertion according to `pmset`.

- [ ] **Step 1: Create `.gitignore`**

```
build/
```

- [ ] **Step 2: Write the test support helpers**

Create `Tests/TestSupport.swift`:

```swift
import Foundation

/// Number of failed checks so far. `Tests/main.swift` uses this as the exit code signal.
var failureCount = 0

func check(_ condition: Bool, _ message: String) {
    if condition {
        print("  ok    \(message)")
    } else {
        print("  FAIL  \(message)")
        failureCount += 1
    }
}

/// True when *this* process currently holds a PreventUserIdleDisplaySleep
/// assertion, according to `pmset` — the same view the user gets from the
/// command line. Checking the kernel's own accounting rather than our
/// instance variable is the point: it proves the assertion is really taken.
func processHoldsDisplayAssertion() -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
    task.arguments = ["-g", "assertions"]
    let pipe = Pipe()
    task.standardOutput = pipe
    try! task.run()
    // Read before waiting, or a full pipe buffer would deadlock.
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()
    let output = String(decoding: data, as: UTF8.self)
    let marker = "pid \(getpid())("
    return output.split(separator: "\n").contains { line in
        line.contains(marker) && line.contains("PreventUserIdleDisplaySleep")
    }
}
```

- [ ] **Step 3: Write the failing test**

Create `Tests/main.swift`:

```swift
import Foundation

print("AwakeController")

let controller = AwakeController()

check(!controller.isOn, "starts off")
check(!processHoldsDisplayAssertion(), "holds no assertion before enable()")

controller.enable()
check(controller.isOn, "isOn is true after enable()")
check(processHoldsDisplayAssertion(), "kernel reports our assertion after enable()")

controller.enable()
check(controller.isOn, "redundant enable() keeps it on")
check(processHoldsDisplayAssertion(), "redundant enable() does not lose the assertion")

controller.disable()
check(!controller.isOn, "isOn is false after disable()")
check(!processHoldsDisplayAssertion(), "kernel released the assertion after disable()")

controller.disable()
check(!controller.isOn, "redundant disable() is a no-op")

controller.toggle()
check(controller.isOn, "toggle() from off turns on")
check(processHoldsDisplayAssertion(), "toggle() on takes the assertion")

controller.toggle()
check(!controller.isOn, "toggle() from on turns off")
check(!processHoldsDisplayAssertion(), "toggle() off releases the assertion")

if failureCount > 0 {
    print("\n\(failureCount) failure(s)")
    exit(1)
}
print("\nall tests passed")
```

- [ ] **Step 4: Write the test runner script**

Create `test.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build/tests

# Sources/main.swift is deliberately excluded: it has top-level code that would
# collide with Tests/main.swift.
swiftc -g \
  Sources/AwakeController.swift \
  Tests/TestSupport.swift \
  Tests/main.swift \
  -o build/tests/CaffeinateTests

build/tests/CaffeinateTests
```

Then: `chmod +x test.sh`

- [ ] **Step 5: Run the test to verify it fails**

Run: `./test.sh`
Expected: FAIL — compile error, `cannot find 'AwakeController' in scope`.

- [ ] **Step 6: Write the implementation**

Create `Sources/AwakeController.swift`:

```swift
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
```

- [ ] **Step 7: Run the test to verify it passes**

Run: `./test.sh`
Expected: PASS — 13 `ok` lines, then `all tests passed`.

If `kernel reports our assertion after enable()` fails but `isOn` passes, the assertion was not really taken — do not paper over it by trusting `isOn`.

- [ ] **Step 8: Commit**

```bash
git add .gitignore Sources/AwakeController.swift Tests/ test.sh
git commit -m "Add AwakeController holding the display-sleep assertion

Verified against pmset rather than the instance variable, so the test
proves the kernel really took the assertion and really released it."
```

---

### Task 2: StatusItemController

**Files:**
- Create: `Sources/StatusItemController.swift`
- Modify: `Tests/main.swift` (append presentation-logic checks)
- Modify: `test.sh` (add `Sources/StatusItemController.swift` to the compile list)

**Interfaces:**
- Consumes: nothing from Task 1. This class is deliberately independent of `AwakeController`.
- Produces:
  - `final class StatusItemController`
  - `static func symbolName(isOn: Bool) -> String`
  - `static func stateTitle(isOn: Bool) -> String`
  - `init(onToggle: @escaping () -> Void)`
  - `func render(isOn: Bool)` — updates icon and menu state line. Task 3 calls this.

Only the two static functions are unit-tested. Instantiating `NSStatusItem` needs a live status bar, so the click routing and icon rendering are verified by hand in Task 5. This is stated plainly rather than faked with a mock that would prove nothing.

- [ ] **Step 1: Write the failing test**

Append to `Tests/main.swift`, immediately **before** the `if failureCount > 0` block:

```swift
print("StatusItemController")

check(StatusItemController.symbolName(isOn: true) == "cup.and.saucer.fill",
      "on state uses the filled cup")
check(StatusItemController.symbolName(isOn: false) == "cup.and.saucer",
      "off state uses the outline cup")
check(StatusItemController.stateTitle(isOn: true) == "Keeping display awake",
      "on state title")
check(StatusItemController.stateTitle(isOn: false) == "Display sleeps normally",
      "off state title")
```

- [ ] **Step 2: Add the new source file to the test compile list**

In `test.sh`, change the `swiftc` invocation to:

```bash
swiftc -g \
  Sources/AwakeController.swift \
  Sources/StatusItemController.swift \
  Tests/TestSupport.swift \
  Tests/main.swift \
  -o build/tests/CaffeinateTests
```

- [ ] **Step 3: Run the test to verify it fails**

Run: `./test.sh`
Expected: FAIL — compile error, `cannot find 'StatusItemController' in scope`.

- [ ] **Step 4: Write the implementation**

Create `Sources/StatusItemController.swift`:

```swift
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
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `./test.sh`
Expected: PASS — 17 `ok` lines, then `all tests passed`.

- [ ] **Step 6: Commit**

```bash
git add Sources/StatusItemController.swift Tests/main.swift test.sh
git commit -m "Add StatusItemController for the menu bar item

Left click toggles, right click opens the menu. Presentation logic is
pure and tested; the AppKit wiring is verified by hand in Task 5."
```

---

### Task 3: AppDelegate, app bundle, and a runnable app

At the end of this task the app runs and toggles from the menu bar. It does not yet start at login.

**Files:**
- Create: `Sources/AppDelegate.swift`
- Create: `Sources/main.swift`
- Create: `Resources/Info.plist`
- Create: `build.sh`

**Interfaces:**
- Consumes: `AwakeController` (`isOn`, `enable()`, `disable()`, `toggle()`) from Task 1; `StatusItemController.init(onToggle:)` and `render(isOn:)` from Task 2.
- Produces: `Caffeinate.app` at `build/Caffeinate.app`; `AppDelegate.stateKey` (`String`, value `"keepAwakeEnabled"`), the `UserDefaults` key Task 5 inspects.

`AppDelegate` is pure wiring and is verified end-to-end in Task 5 rather than by unit test — a unit test here would only assert that three lines call each other.

- [ ] **Step 1: Write the AppDelegate**

Create `Sources/AppDelegate.swift`:

```swift
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
```

- [ ] **Step 2: Write the app entry point**

Create `Sources/main.swift`:

```swift
import AppKit

let app = NSApplication.shared
// Menu bar only: no Dock icon, no app switcher entry, no main window.
// Info.plist's LSUIElement covers bundle launches; this covers running the
// binary directly, as launchd does.
app.setActivationPolicy(.accessory)

let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 3: Write the Info.plist**

Create `Resources/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Caffeinate</string>
    <key>CFBundleDisplayName</key>
    <string>Caffeinate</string>
    <key>CFBundleExecutable</key>
    <string>Caffeinate</string>
    <key>CFBundleIdentifier</key>
    <string>dev.julio.caffeinate</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
```

- [ ] **Step 4: Write build.sh with the `build` subcommand**

Create `build.sh`. Install and uninstall are added in Task 4; this version supports `build` only.

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Caffeinate"
APP_BUNDLE="build/${APP_NAME}.app"

build() {
  rm -rf "$APP_BUNDLE"
  mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"

  swiftc -O \
    Sources/AwakeController.swift \
    Sources/StatusItemController.swift \
    Sources/AppDelegate.swift \
    Sources/main.swift \
    -o "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

  cp Resources/Info.plist "${APP_BUNDLE}/Contents/Info.plist"

  # Ad-hoc signature gives the bundle a stable identity for LaunchServices.
  codesign --force --sign - "$APP_BUNDLE"

  echo "Built ${APP_BUNDLE}"
}

case "${1:-build}" in
  build) build ;;
  *) echo "usage: $0 [build]" >&2; exit 1 ;;
esac
```

Then: `chmod +x build.sh`

- [ ] **Step 5: Build and verify the bundle**

Run: `./build.sh && ls build/Caffeinate.app/Contents/MacOS/`
Expected: `Built build/Caffeinate.app` and a `Caffeinate` executable listed.

- [ ] **Step 6: Verify the unit tests still pass**

Run: `./test.sh`
Expected: PASS — `all tests passed`.

- [ ] **Step 7: Launch and verify the toggle by hand**

```bash
open build/Caffeinate.app
```

Confirm all four, and fix before continuing if any fails:
1. An outline coffee cup appears at the right of the menu bar.
2. No Dock icon appears.
3. Left-clicking fills the cup in; `pmset -g assertions | grep PreventUserIdleDisplaySleep` now shows an assertion owned by `Caffeinate`. Left-clicking again empties the cup and the assertion disappears.
4. Right-clicking opens a menu showing the current state and **Quit Caffeinate**, and Quit exits the app.

- [ ] **Step 8: Commit**

```bash
git add Sources/AppDelegate.swift Sources/main.swift Resources/Info.plist build.sh
git commit -m "Add app delegate, bundle, and build script

Toggling from the menu bar now works. State persists to UserDefaults on
every toggle; applicationWillTerminate releases the assertion without
clearing that value, so the next launch can restore it."
```

---

### Task 4: LaunchAgent install and uninstall

**Files:**
- Modify: `build.sh` (add `install` and `uninstall` subcommands)

**Interfaces:**
- Consumes: `build/Caffeinate.app` from Task 3.
- Produces: `~/Library/LaunchAgents/dev.julio.caffeinate.plist` and an installed app at `$INSTALL_DIR/Caffeinate.app`.

- [ ] **Step 1: Add install and uninstall to build.sh**

Replace the whole of `build.sh` with:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Caffeinate"
BUNDLE_ID="dev.julio.caffeinate"
APP_BUNDLE="build/${APP_NAME}.app"

INSTALL_DIR="${INSTALL_DIR:-/Applications}"
INSTALL_PATH="${INSTALL_DIR}/${APP_NAME}.app"
AGENT_PLIST="${HOME}/Library/LaunchAgents/${BUNDLE_ID}.plist"
DOMAIN="gui/$(id -u)"
SERVICE="${DOMAIN}/${BUNDLE_ID}"

build() {
  rm -rf "$APP_BUNDLE"
  mkdir -p "${APP_BUNDLE}/Contents/MacOS" "${APP_BUNDLE}/Contents/Resources"

  swiftc -O \
    Sources/AwakeController.swift \
    Sources/StatusItemController.swift \
    Sources/AppDelegate.swift \
    Sources/main.swift \
    -o "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

  cp Resources/Info.plist "${APP_BUNDLE}/Contents/Info.plist"

  # Ad-hoc signature gives the bundle a stable identity for LaunchServices.
  codesign --force --sign - "$APP_BUNDLE"

  echo "Built ${APP_BUNDLE}"
}

write_agent_plist() {
  mkdir -p "$(dirname "$AGENT_PLIST")"
  cat > "$AGENT_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${BUNDLE_ID}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${INSTALL_PATH}/Contents/MacOS/${APP_NAME}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key>
        <false/>
    </dict>
    <key>ProcessType</key>
    <string>Interactive</string>
</dict>
</plist>
PLIST
}

install_app() {
  build

  if [ ! -w "$INSTALL_DIR" ]; then
    echo "error: ${INSTALL_DIR} is not writable by $(whoami)." >&2
    echo "Install to your home folder instead:" >&2
    echo "    mkdir -p ~/Applications && INSTALL_DIR=~/Applications ./build.sh install" >&2
    exit 1
  fi

  # Stop any running copy first, ignoring "not loaded".
  launchctl bootout "$SERVICE" 2>/dev/null || true

  rm -rf "$INSTALL_PATH"
  cp -R "$APP_BUNDLE" "$INSTALL_PATH"

  write_agent_plist
  # bootstrap both registers it for future logins and starts it now.
  launchctl bootstrap "$DOMAIN" "$AGENT_PLIST"

  echo "Installed ${INSTALL_PATH}"
  echo "LaunchAgent ${AGENT_PLIST}"
  echo "Running now, and will start at login."
}

uninstall_app() {
  launchctl bootout "$SERVICE" 2>/dev/null || true
  rm -f "$AGENT_PLIST"
  rm -rf "$INSTALL_PATH"
  echo "Removed ${INSTALL_PATH} and its LaunchAgent."
}

case "${1:-build}" in
  build)     build ;;
  install)   install_app ;;
  uninstall) uninstall_app ;;
  *) echo "usage: $0 [build|install|uninstall]" >&2; exit 1 ;;
esac
```

- [ ] **Step 2: Install and verify registration**

```bash
./build.sh install
launchctl print gui/$(id -u)/dev.julio.caffeinate | grep -E 'state|runatload|program'
```

Expected: state is `running`, and the program path points at the installed bundle.

- [ ] **Step 3: Verify KeepAlive is the dict form, not the boolean**

Run: `/usr/libexec/PlistBuddy -c "Print :KeepAlive" ~/Library/LaunchAgents/dev.julio.caffeinate.plist`
Expected:

```
Dict {
    SuccessfulExit = false
}
```

If this prints `true`, Quit will be broken — fix before continuing.

- [ ] **Step 4: Verify a clean Quit stays quit**

Right-click the menu bar cup, choose **Quit Caffeinate**, wait ~15 seconds (longer than launchd's 10-second respawn throttle), then run:

```bash
pgrep -x Caffeinate || echo "stayed quit (correct)"
```

Expected: `stayed quit (correct)`. If the process came back, `KeepAlive` is wrong.

- [ ] **Step 5: Restart it for the next task**

```bash
launchctl kickstart gui/$(id -u)/dev.julio.caffeinate
```

Expected: the cup reappears in the menu bar.

- [ ] **Step 6: Commit**

```bash
git add build.sh
git commit -m "Add LaunchAgent install and uninstall

KeepAlive is the dict {SuccessfulExit: false}, not boolean true, so a
crash is revived but a deliberate Quit stays quit."
```

---

### Task 5: End-to-end failure-mode verification

The whole design rests on two claims: the kernel releases the assertion when the app dies, and launchd brings the app back awake. This task proves both against the running system.

**Files:**
- Create: `README.md`

**Interfaces:**
- Consumes: an installed, running app from Task 4.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Turn keep-awake on and confirm the assertion**

Left-click the cup so it fills, then:

```bash
pmset -g assertions | grep PreventUserIdleDisplaySleep
```

Expected: a line attributing the assertion to `Caffeinate`.

- [ ] **Step 2: Confirm the state was persisted**

```bash
defaults read dev.julio.caffeinate keepAwakeEnabled
```

Expected: `1`.

If this errors with "does not exist", the app is reading and writing a different defaults domain than expected — check `CFBundleIdentifier` in the installed `Info.plist`.

- [ ] **Step 3: Kill the app and confirm the kernel released the assertion**

This is the core failure-mode test: an orphaned assertion here would mean a Mac stuck awake with no UI to stop it.

```bash
kill -9 "$(pgrep -x Caffeinate)"
sleep 1
pmset -g assertions | grep PreventUserIdleDisplaySleep || echo "assertion released (correct)"
```

Expected: `assertion released (correct)`.

- [ ] **Step 4: Confirm launchd revives it, awake**

```bash
sleep 15
pgrep -x Caffeinate && pmset -g assertions | grep PreventUserIdleDisplaySleep
```

Expected: a PID, and the assertion is back, attributed to `Caffeinate`. The menu bar cup is filled again.

This is the whole point of persisting state: a relaunch that came back empty would silently stop keeping the display awake.

- [ ] **Step 5: Confirm login registration**

```bash
launchctl print gui/$(id -u)/dev.julio.caffeinate | grep -i runatload
```

Expected: `runatload = 1`. Reboot behavior is verified through this registration rather than by rebooting the machine.

- [ ] **Step 6: Write the README**

Create `README.md`:

````markdown
# Caffeinate

A macOS menu bar app that keeps the display awake. Coffee cup icon, one click.

- **Left-click** the cup to toggle. Outline = display sleeps normally, filled = staying awake.
- **Right-click** for the current state and Quit.

It holds the same IOKit power assertion (`PreventUserIdleDisplaySleep`) that
`caffeinate -d` uses, so it shows up in `pmset -g assertions` the same way.

## Install

```bash
./build.sh install
```

Installs to `/Applications` and registers a LaunchAgent, so it starts at login
and restarts itself if it ever crashes. If `/Applications` is not writable:

```bash
mkdir -p ~/Applications && INSTALL_DIR=~/Applications ./build.sh install
```

## Uninstall

```bash
./build.sh uninstall
```

## Develop

```bash
./test.sh     # unit tests
./build.sh    # build build/Caffeinate.app without installing
```

## Design notes

Two decisions are load-bearing and should not be "simplified":

- **The app holds the assertion itself instead of spawning `caffeinate`.** An
  assertion is owned by its creating process, so the kernel releases it on any
  death including SIGKILL. A spawned child could be orphaned and leave the Mac
  awake forever with no UI left to stop it.
- **The LaunchAgent uses `KeepAlive = { SuccessfulExit: false }`, not `true`.**
  Boolean `true` would relaunch the app after a deliberate Quit and make Quit
  appear broken. Persisting the on/off state matters for the same reason: after
  a crash, launchd restarts the app, and it must come back *awake* or it would
  silently stop doing its job.

Full design: `docs/superpowers/specs/2026-08-07-caffeinate-menubar-design.md`
````

- [ ] **Step 7: Commit**

```bash
git add README.md
git commit -m "Add README

Records the two load-bearing decisions (process-owned assertion,
KeepAlive SuccessfulExit) so they survive future cleanup."
```

---

## Self-Review

**Spec coverage:** Left/right click and icon states → Task 2. IOKit assertion → Task 1. LaunchAgent `RunAtLoad` + `KeepAlive{SuccessfulExit:false}` → Task 4. `UserDefaults` persistence and restore → Task 3. Three-component split → Tasks 1–3. `LSUIElement` + `.accessory` → Task 3. `build.sh build|install|uninstall` and the unwritable-`/Applications` message → Tasks 3–4. All four spec verification items → Task 5 (steps 1, 3–4, and Task 4 step 4, plus Task 5 step 5). Symbol fallback → Task 2. Out-of-scope items appear nowhere. No gaps.

**Placeholder scan:** No TBD/TODO. Every code step has literal code. Every run step has an exact command and expected output.

**Type consistency:** `AwakeController.enable/disable/toggle/isOn` used identically in Tasks 1 and 3. `StatusItemController.init(onToggle:)` and `render(isOn:)` defined in Task 2, called with those exact labels in Task 3. `AppDelegate.stateKey` = `"keepAwakeEnabled"` matches the `defaults read` key in Task 5. `BUNDLE_ID` matches `CFBundleIdentifier`, the LaunchAgent `Label`, and every `launchctl` service target.

**Pre-verified against the toolchain:** the `IOPMAssertionCreateWithName` call, the `pmset`-based probe (assertion appears under our own PID and vanishes on release), `sendAction(on:)` on `NSStatusBarButton`, and the existence of both SF Symbols were all compiled and run on this machine before the plan was written.
