#!/bin/bash
set -e

cd "$(dirname "$0")"

if ! command -v xcodegen &>/dev/null; then
    echo "Installing xcodegen..."
    brew install xcodegen
fi

echo "Generating Xcode project..."
xcodegen generate

echo "Building..."
xcodebuild \
    -scheme QuickReminder \
    -configuration Debug \
    -derivedDataPath build \
    clean build \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO

echo "Done. App location:"
find build -name "QuickReminder.app" -maxdepth 6 | head -1
