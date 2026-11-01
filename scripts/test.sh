#!/bin/bash
# Runs the test suite. With only the Command Line Tools installed, the Swift Testing macro
# plugin lives in a subfolder the compiler doesn't search by default, so point it there.
set -euo pipefail
cd "$(dirname "$0")/.."

PLUGINS="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [ -d "$PLUGINS" ]; then
    exec swift test -Xswiftc -plugin-path -Xswiftc "$PLUGINS" "$@"
else
    exec swift test "$@"
fi
