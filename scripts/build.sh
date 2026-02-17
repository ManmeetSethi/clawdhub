#!/bin/bash
# Build ClawdHub from the command line
# Outputs .app bundle to build/ directory

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/../ClawdHub"
BUILD_DIR="$SCRIPT_DIR/../build"
MIN_XCODE_VERSION="15.0"

# --- Xcode checks ---

if ! command -v xcodebuild &>/dev/null; then
    echo "ERROR: xcodebuild not found."
    echo ""
    echo "Full Xcode.app is required to build ClawdHub."
    echo "Command Line Tools alone are NOT sufficient."
    echo ""
    echo "Install Xcode from:"
    echo "  Mac App Store: https://apps.apple.com/app/xcode/id497799835"
    echo ""
    echo "After installing, run:"
    echo "  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
    echo "  sudo xcodebuild -license accept"
    exit 1
fi

DEVELOPER_DIR=$(xcode-select -p 2>/dev/null)
if [[ "$DEVELOPER_DIR" == "/Library/Developer/CommandLineTools" ]]; then
    echo "ERROR: xcode-select is pointing to Command Line Tools, not Xcode.app."
    echo ""
    echo "Run: sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer"
    exit 1
fi

if [[ ! -d "$DEVELOPER_DIR" ]]; then
    echo "ERROR: Developer directory does not exist: $DEVELOPER_DIR"
    echo "Install Xcode.app and re-run."
    exit 1
fi

XCODE_VERSION=$(xcodebuild -version 2>/dev/null | head -1 | awk '{print $2}')
if [[ "$(printf '%s\n' "$MIN_XCODE_VERSION" "$XCODE_VERSION" | sort -V | head -1)" != "$MIN_XCODE_VERSION" ]]; then
    echo "ERROR: Xcode $XCODE_VERSION found, but >= $MIN_XCODE_VERSION is required."
    exit 1
fi

echo "Building ClawdHub... (Xcode $XCODE_VERSION)"

set +o pipefail
xcodebuild build \
    -project "$PROJECT_DIR/ClawdHub.xcodeproj" \
    -scheme ClawdHub \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    CODE_SIGN_IDENTITY="-" \
    2>&1 | tail -20
set -o pipefail

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/Release/ClawdHub.app"

if [ -d "$APP_PATH" ]; then
    echo ""
    echo "Build succeeded!"

    # Install to Applications
    echo "Installing to /Applications..."
    rm -rf /Applications/ClawdHub.app
    cp -r "$APP_PATH" /Applications/ClawdHub.app
    echo "Installed to /Applications/ClawdHub.app"

    # Relaunch the app (quit existing instance first — `open` won't restart a running app)
    echo "Launching ClawdHub..."
    osascript -e 'tell application "ClawdHub" to quit' 2>/dev/null
    sleep 1
    # Fallback: force kill if graceful quit didn't work
    pkill -x ClawdHub 2>/dev/null
    sleep 0.5
    open /Applications/ClawdHub.app
else
    echo ""
    echo "Build failed — check output above."
    exit 1
fi
