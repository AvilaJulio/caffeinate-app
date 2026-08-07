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
