# Caffeinate

A macOS menu bar app that keeps the display awake. Coffee cup icon, one click.

![Caffeinate's coffee cup in the macOS menu bar](docs/menubar.png)

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
