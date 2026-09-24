#!/usr/bin/env bash
# Assemble dist/homerowless.app from a SwiftPM release build. No .xcodeproj.
#   VERSION=1.2.3      stamps CFBundleShortVersionString and CFBundleVersion
#   UNIVERSAL=1        builds arm64 + x86_64
#   CODESIGN_IDENTITY  signing identity (default ad-hoc)
set -euo pipefail
cd "$(dirname "$0")/.."
ARGS=(-c release --product App)
[[ "${UNIVERSAL:-0}" == 1 ]] && ARGS+=(--arch arm64 --arch x86_64)
swift build "${ARGS[@]}"
BIN=$(swift build "${ARGS[@]}" --show-bin-path)   # never hardcode .build/release
APP=dist/homerowless.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/App" "$APP/Contents/MacOS/homerowless"
ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [[ -n "${VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"
# Sparkle only replaces the app when the update's signature matches the installed one, and a
# changed signature silently revokes the Accessibility grant. Releases sign with the stable
# "homerowless Release" identity. Dev builds: CODESIGN_IDENTITY=HomerowlessDev (see scripts/make-signing-cert.md).
IDENTITY="${CODESIGN_IDENTITY:--}"
SP="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
for part in XPCServices/Installer.xpc XPCServices/Downloader.xpc Autoupdate Updater.app; do
  codesign --force --sign "$IDENTITY" "$SP/$part"
done
codesign --force --sign "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "$IDENTITY" --identifier com.cohnesor.homerowless "$APP"
codesign --verify --deep --strict "$APP"
echo "built $APP (signed: $IDENTITY)"
