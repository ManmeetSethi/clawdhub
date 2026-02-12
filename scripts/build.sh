#!/bin/bash
# Build ClawdHub from the command line
# Outputs .app bundle to build/ directory

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/../ClawdHub"
BUILD_DIR="$SCRIPT_DIR/../build"

echo "Building ClawdHub..."

xcodebuild build \
    -project "$PROJECT_DIR/ClawdHub.xcodeproj" \
    -scheme ClawdHub \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/DerivedData" \
    CODE_SIGN_IDENTITY="-" \
    2>&1 | tail -20

APP_PATH="$BUILD_DIR/DerivedData/Build/Products/Release/ClawdHub.app"

if [ -d "$APP_PATH" ]; then
    echo ""
    echo "Build succeeded!"

    # Install to Applications
    echo "Installing to /Applications..."
    rm -rf /Applications/ClawdHub.app
    cp -r "$APP_PATH" /Applications/ClawdHub.app
    echo "Installed to /Applications/ClawdHub.app"

    # Launch the app
    echo "Launching ClawdHub..."
    open /Applications/ClawdHub.app
else
    echo ""
    echo "Build failed — check output above."
    exit 1
fi
