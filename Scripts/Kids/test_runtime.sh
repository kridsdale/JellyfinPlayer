#!/bin/sh
# Compile production utilities and the isolated defaults fixture in Swift 6.
set -eu
REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
RUNTIME_TEST_BUILD=$(mktemp -d "${TMPDIR:-/tmp}/kids-runtime-tests.XXXXXX")
trap 'rm -rf "$RUNTIME_TEST_BUILD"' EXIT HUP INT TERM
xcrun swiftc -swift-version 6 -parse-as-library \
  "$REPO_ROOT/Scripts/Kids/tests/runtime/Fixtures/SwizzleDefaults.swift" \
  "$REPO_ROOT/Scripts/Kids/tests/runtime/SwizzleDefaultsTests.swift" \
  -o "$RUNTIME_TEST_BUILD/swizzle-defaults-tests"
"$RUNTIME_TEST_BUILD/swizzle-defaults-tests"
xcrun swiftc -swift-version 6 -parse-as-library \
  "$REPO_ROOT/Packages/SwiftfinUIState/Sources/SwiftfinUIState/PokeIntervalTimer.swift" \
  "$REPO_ROOT/Scripts/Kids/tests/runtime/PokeIntervalTimerTests.swift" \
  -o "$RUNTIME_TEST_BUILD/poke-interval-tests"
"$RUNTIME_TEST_BUILD/poke-interval-tests"
xcrun swiftc -swift-version 6 -parse-as-library \
  "$REPO_ROOT/Packages/KidsPlayback/Sources/KidsPlayback/PlaybackBitrateMeasurement.swift" \
  "$REPO_ROOT/Scripts/Kids/tests/runtime/PlaybackBitrateMeasurementTests.swift" \
  -o "$RUNTIME_TEST_BUILD/bitrate-measurement-tests"
"$RUNTIME_TEST_BUILD/bitrate-measurement-tests"
