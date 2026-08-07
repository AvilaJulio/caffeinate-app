# Caffeinate menu bar app — design

**Date:** 2026-08-07
**Status:** Approved, ready for implementation planning

## Purpose

A macOS status bar app that keeps the display awake, toggled by clicking a coffee
cup icon in the menu bar. It must survive its own crashes and machine reboots
without the user having to remember to relaunch it, and it must never leave the
Mac stuck awake with no visible way to turn it off.

## Behavior

- A coffee cup icon sits in the status bar (right side of the menu bar).
- **Left-click** toggles keep-awake on and off.
  - Off: `cup.and.saucer` (outline)
  - On: `cup.and.saucer.fill` (filled)
- **Right-click** opens a menu showing the current state and a **Quit** item.
- No Dock icon, no windows, no preferences UI.
- On launch, the app restores whatever state it was last in.

"Keep awake" means the same thing `caffeinate -d` means: prevent idle *display*
sleep. It does not prevent sleep on lid close, and it does not prevent a
user-initiated sleep.

## Mechanism: IOKit assertion, not a subprocess

The app takes the power assertion itself rather than spawning `/usr/bin/caffeinate`:

```
IOPMAssertionCreateWithName(
    kIOPMAssertionTypePreventUserIdleDisplaySleep,
    kIOPMAssertionLevelOn,
    reason,
    &assertionID)
```

This is what `caffeinate -d` does internally, and it appears identically in
`pmset -g assertions`.

**Rationale — this is the core failure-mode decision.** An assertion is owned by
the process that created it, and the kernel releases it when that process dies,
by any means: clean exit, crash, `kill -9`, panic. With a spawned `caffeinate`
child there is always some window in which the parent dies and the child is
orphaned, leaving the Mac permanently awake with no UI left to stop it. The
`caffeinate -w <pid>` flag narrows that window but does not close it. Holding the
assertion directly removes the orphan case entirely rather than defending
against it.

## Mechanism: LaunchAgent for crash and reboot recovery

`build.sh install` writes `~/Library/LaunchAgents/dev.julio.caffeinate.plist`:

- `RunAtLoad: true` — starts at login, so a reboot brings it back.
- `KeepAlive: { SuccessfulExit: false }` — relaunch **only** on a bad exit.

`KeepAlive: { SuccessfulExit: false }` is deliberate and must not be simplified to
`KeepAlive: true`. Plain `true` relaunches the job unconditionally, including
after the user chooses Quit, which would make Quit appear broken. With
`SuccessfulExit: false`, a clean exit(0) stays quit until next login, while a
crash or signal death is revived. launchd throttles respawns to a 10-second
minimum, so a crash-on-launch bug cannot spin the CPU.

## State persistence

The on/off state is written to `UserDefaults` on every toggle and read back at
launch.

This is not a convenience feature; it is what makes crash recovery actually work.
Without it, launchd faithfully relaunches the app after a crash but the app comes
back **off**, so the display starts sleeping again silently and the user does not
notice. One rule applies to every launch — crash, clean quit, or login — so there
is only one behavior to reason about.

## Components

Three units with no knowledge of each other's internals.

### `AwakeController`

The only code that touches IOKit.

- `var isOn: Bool { get }`
- `func enable()` — no-op if the assertion is already held
- `func disable()` — releases the assertion and clears the stored ID
- `func toggle()`

Holds one `IOPMAssertionID`. Knows nothing about UI or persistence.

### `StatusItemController`

Owns the `NSStatusItem`.

- Renders the button image from a bool, using template images so the icon tracks
  light and dark menu bars automatically.
- Routes left-click to a toggle callback supplied by the caller.
- Right-click opens a menu with a state line and **Quit**.

Knows nothing about IOKit or `UserDefaults`.

`NSImage(systemSymbolName:accessibilityDescription:)` returns an optional. If the
symbol is unavailable the controller falls back to a "☕" text title, so the status
item is never invisible.

### `AppDelegate`

Wiring only. Reads saved state at launch and applies it; on toggle, flips
`AwakeController` and writes the new value back; on terminate, releases the
assertion explicitly (redundant with the kernel, but explicit).

## Files

```
Sources/AwakeController.swift
Sources/StatusItemController.swift
Sources/AppDelegate.swift
Sources/main.swift              NSApplication bootstrap, .accessory policy
Resources/Info.plist            LSUIElement=true, bundle id dev.julio.caffeinate
build.sh                        build | install | uninstall
```

`main.swift` sets `NSApp.setActivationPolicy(.accessory)`; `Info.plist` sets
`LSUIElement=true`. Both are needed: the plist keeps it out of the Dock at launch,
the policy call keeps it out if launched directly from the binary.

## build.sh

- `./build.sh` — `swiftc` the sources, assemble `Caffeinate.app` in the project
  directory.
- `./build.sh install` — copy to `/Applications/Caffeinate.app`, write the
  LaunchAgent plist, then `launchctl bootout gui/$UID/dev.julio.caffeinate`
  (ignoring failure when not loaded) followed by `launchctl bootstrap gui/$UID
  <plist>`, so it starts immediately rather than only at next login.
- `./build.sh uninstall` — bootout, remove the plist, remove the app.

If `/Applications` is not writable, install fails with an explicit message rather
than silently requiring sudo.

Install and uninstall are the only "start at login" control. The app does not
drive `launchctl` at runtime and has no login-item checkbox.

## Verification

Manual, against the assertion itself rather than against the UI. Unit tests are
not meaningful here; what matters is whether macOS actually holds the assertion.

1. **Toggle:** `pmset -g assertions` shows no `PreventUserIdleDisplaySleep` when
   off; shows it attributed to Caffeinate when on.
2. **Crash recovery:** with keep-awake on, `kill -9` the app. The assertion
   disappears immediately, proving the kernel released it and no orphan remains.
   launchd relaunches within ~10s and the app comes back **on** with the
   assertion re-taken.
3. **Clean quit:** Quit from the menu. The process stays gone, the assertion is
   released, and launchd does not revive it.
4. **Login registration:** `launchctl print gui/$UID/dev.julio.caffeinate`
   confirms `RunAtLoad`. Reboot behavior is verified via this registration rather
   than by rebooting.

## Out of scope

Timed modes (`caffeinate -t`), preventing system sleep as well as display sleep
(`caffeinate -i`/`-s`), a preferences window, and an in-app login-item toggle.
