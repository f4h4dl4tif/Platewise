#!/bin/bash
# Builds Platewise.app into ./build
set -euo pipefail
cd "$(dirname "$0")"

# The macOS 27 SDK in Command Line Tools lacks the SwiftUI macro plugin (@State etc.),
# so build against the 26.5 SDK when no SDK is chosen explicitly.
if [ -z "${SDKROOT:-}" ] && [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]; then
  export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
fi

if [ "${UNIVERSAL:-0}" = "1" ]; then
  swift build -c release --arch arm64 --arch x86_64
  BIN=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Platewise
else
  swift build -c release
  BIN=.build/release/Platewise
fi

ICON=Resources/AppIcon.icns
if [ ! -f "$ICON" ]; then
  TMP=$(mktemp -d)
  swift Scripts/make-icon.swift "$TMP/icon.png"
  SET="$TMP/AppIcon.iconset"; mkdir "$SET"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$TMP/icon.png" --out "$SET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) "$TMP/icon.png" --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$SET" -o "$ICON"
  rm -rf "$TMP"
fi

# Apple Intelligence helper: image input to the on-device model needs the macOS 27 SDK, which can't build the
# SwiftUI app with the Command Line Tools, so the helper is compiled on its own (Apple silicon only).
HELPER=.build/platewise-ai
SDK27=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX27*.sdk 2>/dev/null | sort -V | tail -1)
if [ -n "$SDK27" ]; then
  SDKROOT="$SDK27" swiftc -O -parse-as-library -target arm64-apple-macos27.0 Helper/PlatewiseAI.swift -o "$HELPER"
else
  echo "Warning: no macOS 27 SDK found; building without Apple Intelligence (Snap & Cook will be unavailable)"
  rm -f "$HELPER"
fi

APP=build/Platewise.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Platewise"
[ -f "$HELPER" ] && cp "$HELPER" "$APP/Contents/MacOS/platewise-ai"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"

# Sign with a stable local certificate so macOS permissions (camera) and the
# Keychain-stored API keys survive rebuilds. Falls back to ad-hoc signing.
KC="$(pwd)/signing/platewise.keychain-db"
if [ -f "$KC" ] && [ -f signing/keychain-password.txt ]; then
  security unlock-keychain -p "$(cat signing/keychain-password.txt)" "$KC"
  ID=$(security find-identity "$KC" | awk '/Platewise Local Signing/ {print $2; exit}')
  codesign --force --deep --keychain "$KC" --sign "$ID" -i local.platewise.Platewise "$APP"
  echo "Signed with Platewise Local Signing ($ID)"
else
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
  echo "Warning: ad-hoc signed; permissions will reset on every rebuild (run Scripts/make-signing.sh once)"
fi

echo "Built $(pwd)/$APP"
