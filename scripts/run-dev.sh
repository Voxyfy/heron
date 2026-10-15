#!/bin/sh
# Builds Heron and runs it, signed with your Apple Development certificate.
set -e
cd "$(dirname "$0")/.."
IDENTITY="${HERON_SIGN_IDENTITY:-Apple Development}"
xcodegen generate >/dev/null
xcodebuild -project Heron.xcodeproj -scheme Heron -configuration Debug -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO build | grep -E "error:|BUILD" || true
APP=build/Build/Products/Debug/Heron.app
codesign --force --deep --options runtime --sign "$IDENTITY" \
  --entitlements Heron/Resources/Heron.entitlements "$APP"
pkill -f "$APP/Contents/MacOS/Heron" 2>/dev/null || true
open "$APP"
