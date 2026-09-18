#!/bin/bash
# Compile the app sources (minus the @main app file) together with Tests/*.swift
# into a small command-line runner and execute it. No Xcode project needed.
set -euo pipefail
cd "$(dirname "$0")/.."
TC=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin
SDK=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
OUT=build/tests/QuickReminderTests
mkdir -p build/tests
SOURCES=()
while IFS= read -r -d '' f; do SOURCES+=("$f"); done < <(find Sources Tests -name '*.swift' ! -name 'QuickReminderApp.swift' -print0 | sort -z)
"$TC/swiftc" -sdk "$SDK" -target arm64-apple-macos26.0 -swift-version 6 -Onone -g \
    -module-name QuickReminderTests \
    -framework AppKit -framework SwiftUI -framework EventKit -framework Carbon \
    "${SOURCES[@]}" -o "$OUT"
"$OUT"
