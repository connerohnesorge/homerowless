#!/usr/bin/env bash
# Assemble dist/homerowless.app from a SwiftPM release build. No .xcodeproj.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product App
BIN=$(swift build -c release --show-bin-path)   # never hardcode .build/release
APP=dist/homerowless.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/App" "$APP/Contents/MacOS/homerowless"
cp Resources/Info.plist "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
# Dev builds: CODESIGN_IDENTITY=HomerowlessDev keeps the TCC Accessibility grant across rebuilds (see scripts/make-signing-cert.md).
IDENTITY="${CODESIGN_IDENTITY:--}"
codesign --force --sign "$IDENTITY" --identifier com.cohnesor.homerowless "$APP"
echo "built $APP (signed: $IDENTITY)"
