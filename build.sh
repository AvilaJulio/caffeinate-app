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
