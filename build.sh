#!/bin/bash
# Build QuickReminder.app directly with swiftc, bypassing xcodebuild.
#
# `xcodebuild`/`xcrun`/`swift` are blocked on this machine by an un-accepted
# Xcode license (needs sudo we don't have), so this script drives the
# toolchain binaries directly instead.
#
# Usage:
#   ./build.sh        - build only
#   ./build.sh run    - build, kill any running QuickReminder, then open it

set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="QuickReminder"
BUNDLE_ID="com.jholec.QuickReminder"
BUILD_DIR="build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
EXECUTABLE="$MACOS_DIR/$APP_NAME"

DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
SWIFTC="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc"
SDK="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
TARGET="arm64-apple-macos26.0"

CONFIGURATION="${CONFIGURATION:-Debug}"

if [[ ! -x "$SWIFTC" ]]; then
    echo "error: swiftc not found at $SWIFTC" >&2
    exit 1
fi

if [[ ! -d "$SDK" ]]; then
    echo "error: macOS SDK not found at $SDK" >&2
    exit 1
fi

# Keep the .xcodeproj in sync for whenever the user opens Xcode directly.
# This is best-effort and never blocks the swiftc build below.
if command -v xcodegen &>/dev/null; then
    echo "Regenerating Xcode project (xcodegen)..."
    xcodegen generate || echo "warning: xcodegen generate failed, continuing with swiftc build" >&2
elif [[ -x /opt/homebrew/bin/xcodegen ]]; then
    echo "Regenerating Xcode project (xcodegen)..."
    /opt/homebrew/bin/xcodegen generate || echo "warning: xcodegen generate failed, continuing with swiftc build" >&2
else
    echo "warning: xcodegen not found, skipping .xcodeproj regeneration" >&2
fi

echo "Cleaning previous build..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

echo "Compiling sources with swiftc ($CONFIGURATION)..."

SWIFT_FILES=()
while IFS= read -r -d '' f; do
    SWIFT_FILES+=("$f")
done < <(find Sources -name '*.swift' -print0 | sort -z)

if [[ ${#SWIFT_FILES[@]} -eq 0 ]]; then
    echo "error: no Swift source files found under Sources/" >&2
    exit 1
fi

OPT_FLAGS=(-O)
if [[ "$CONFIGURATION" == "Debug" ]]; then
    OPT_FLAGS=(-Onone -g)
fi

set +e
"$SWIFTC" \
    -sdk "$SDK" \
    -target "$TARGET" \
    -swift-version 6 \
    "${OPT_FLAGS[@]}" \
    -module-name "$APP_NAME" \
    -framework AppKit \
    -framework SwiftUI \
    -framework EventKit \
    -framework Carbon \
    -o "$EXECUTABLE" \
    "${SWIFT_FILES[@]}"
COMPILE_STATUS=$?
set -e

if [[ $COMPILE_STATUS -ne 0 ]]; then
    echo "" >&2
    echo "Compilation FAILED (exit $COMPILE_STATUS). See swiftc errors above." >&2
    exit $COMPILE_STATUS
fi

echo "Assembling app bundle..."

# CFBundleVersion auto-increments via a build timestamp so each build is
# distinguishable, while CFBundleShortVersionString stays as authored.
BUILD_VERSION="$(date +%Y%m%d%H%M%S)"
SHORT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist 2>/dev/null || echo '1.0')"

# Resources/Info.plist is authored/maintained by xcodegen (project.yml) and
# still contains xcodebuild-style $(VAR) placeholders for a few keys. Render
# those into a concrete Contents/Info.plist for the swiftc-built bundle.
sed \
    -e "s/\$(DEVELOPMENT_LANGUAGE)/en/g" \
    -e "s/\$(EXECUTABLE_NAME)/$APP_NAME/g" \
    -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/$BUNDLE_ID/g" \
    -e "s/\$(PRODUCT_NAME)/$APP_NAME/g" \
    Resources/Info.plist > "$CONTENTS_DIR/Info.plist"

/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_VERSION" "$CONTENTS_DIR/Info.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SHORT_VERSION" "$CONTENTS_DIR/Info.plist" >/dev/null 2>&1 || true

printf 'APPL????' > "$CONTENTS_DIR/PkgInfo"

if [[ -d Resources/Assets.xcassets ]]; then
    : # actool is not used/needed; Assets.xcassets has nothing meaningful in it.
fi

# Prefer a stable developer identity (TCC grants for Reminders then survive rebuilds);
# fall back to ad-hoc ("-") when none is in the keychain. Override with SIGN_ID=...
if [[ -z "${SIGN_ID:-}" ]]; then
    SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null | grep -o '"Apple Development: [^"]*"' | head -1 | tr -d '"')"
    SIGN_ID="${SIGN_ID:--}"
fi
echo "Code signing (identity: $SIGN_ID)..."

SIGN_LOG="$(mktemp -t quickreminder-codesign)"
trap 'rm -f "$SIGN_LOG"' EXIT
# Intentionally unsandboxed (see project.yml) — hardened runtime only. Never ship a
# bundle whose signature or runtime flag did not stick.
if ! codesign --force --sign "$SIGN_ID" --options runtime "$APP_BUNDLE" 2>"$SIGN_LOG"; then
    echo "error: codesign failed:" >&2
    cat "$SIGN_LOG" >&2
    exit 1
fi
if ! codesign --verify --deep --strict "$APP_BUNDLE" 2>"$SIGN_LOG"; then
    echo "error: codesign --verify failed:" >&2
    cat "$SIGN_LOG" >&2
    exit 1
fi
SIGN_INFO="$(codesign -dv "$APP_BUNDLE" 2>&1 || true)"
if [[ "$SIGN_INFO" != *"runtime"* ]]; then
    echo "error: hardened runtime flag missing from the signed bundle" >&2
    exit 1
fi

echo "Done. App bundle: $APP_BUNDLE"

if [[ "${1:-}" == "run" ]]; then
    echo "Killing any running $APP_NAME process..."
    pkill -x "$APP_NAME" 2>/dev/null || true
    sleep 0.3
    echo "Opening $APP_BUNDLE..."
    open "$APP_BUNDLE"
fi
