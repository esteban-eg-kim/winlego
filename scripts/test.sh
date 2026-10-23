#!/usr/bin/env bash
# swift test, also with only the Command Line Tools installed: their swift does not
# always find the Swift Testing macro plugin on its own ("plugin for module
# 'TestingMacros' not found"), so point it there.
set -euo pipefail
cd "$(dirname "$0")/.."
plugins="$(xcode-select -p)/usr/lib/swift/host/plugins/testing"
if [ -d "$plugins" ]; then
  exec swift test -Xswiftc -plugin-path -Xswiftc "$plugins" "$@"
fi
exec swift test "$@"
