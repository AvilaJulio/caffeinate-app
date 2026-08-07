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
