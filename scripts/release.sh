#!/bin/sh
# Builds a release of Heron and prepares everything a release needs:
#   build/release/Heron-<version>.dmg   signed with Developer ID, notarized and stapled
#   docs/appcast.xml                    a new <item> with Sparkle's EdDSA signature
# Then: commit docs/, push, and attach the DMG to a GitHub release tagged v<version>.
#
# One-time setup (your Keychain, not the repo):
#   xcrun notarytool store-credentials heron --apple-id <apple id> --team-id 4U5QVH3U6A --password <app-specific password>
#   build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys     # prints the public key
#   then put that public key in project.yml under SPARKLE_PUBLIC_ED_KEY
#
# Usage: scripts/release.sh            (version comes from project.yml MARKETING_VERSION)
set -e
cd "$(dirname "$0")/.."

IDENTITY="${HERON_DEVELOPER_ID:-Developer ID Application: BATUHAN HAYMANA (4U5QVH3U6A)}"
PROFILE="${HERON_NOTARY_PROFILE:-heron}"
VERSION=$(grep MARKETING_VERSION project.yml | head -1 | sed 's/.*"\(.*\)".*/\1/')
BUILD=$(grep CURRENT_PROJECT_VERSION project.yml | head -1 | sed 's/.*"\(.*\)".*/\1/')
OUT=build/release
APP="$OUT/Heron.app"
DMG="$OUT/Heron-$VERSION.dmg"
SPARKLE=build/SourcePackages/artifacts/sparkle/Sparkle/bin

echo "▸ Heron $VERSION ($BUILD)"
if ! grep -q 'SPARKLE_PUBLIC_ED_KEY: ".\+"' project.yml; then
  echo "SPARKLE_PUBLIC_ED_KEY is empty in project.yml; run generate_keys first." >&2
  exit 1
fi

rm -rf "$OUT" && mkdir -p "$OUT"
xcodegen generate >/dev/null
xcodebuild -project Heron.xcodeproj -scheme Heron -configuration Release -derivedDataPath build \
  -archivePath "$OUT/Heron.xcarchive" archive \
  CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=4U5QVH3U6A \
  OTHER_CODE_SIGN_FLAGS="--timestamp" | grep -E "error:|ARCHIVE" || true
cp -R "$OUT/Heron.xcarchive/Products/Applications/Heron.app" "$APP"

echo "▸ Signing"
# Sparkle's helpers must be signed before the app that contains them.
codesign --force --options runtime --timestamp --sign "$IDENTITY" \
  "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
codesign --force --options runtime --timestamp --sign "$IDENTITY" \
  "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Downloader.xpc"
codesign --force --options runtime --timestamp --sign "$IDENTITY" \
  "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
codesign --force --options runtime --timestamp --sign "$IDENTITY" \
  "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --options runtime --timestamp --sign "$IDENTITY" \
  --entitlements Heron/Resources/Heron.entitlements "$APP"
codesign --verify --deep --strict "$APP"

echo "▸ DMG"
STAGE="$OUT/dmg"
mkdir -p "$STAGE" && cp -R "$APP" "$STAGE/" && ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Heron" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

echo "▸ Notarizing (a few minutes)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

echo "▸ Appcast"
SIG=$("$SPARKLE/sign_update" "$DMG" | sed 's/^sparkle:edSignature="\([^"]*\)" length="\([0-9]*\)".*/\1 \2/')
EDSIG=${SIG%% *}; LENGTH=${SIG##* }
DATE=$(date -R)
ITEM="    <item>
      <title>Heron $VERSION</title>
      <pubDate>$DATE</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://voxyfy.github.io/heron/releases/$VERSION.html</sparkle:releaseNotesLink>
      <enclosure url=\"https://github.com/Voxyfy/heron/releases/download/v$VERSION/Heron-$VERSION.dmg\"
                 sparkle:edSignature=\"$EDSIG\" length=\"$LENGTH\" type=\"application/octet-stream\"/>
    </item>"
python3 - "$ITEM" <<'EOF'
import sys, pathlib
p = pathlib.Path("docs/appcast.xml"); s = p.read_text()
marker = "    <!-- scripts/release.sh appends one <item> per release here. -->"
p.write_text(s.replace(marker, marker + "\n" + sys.argv[1], 1))
EOF
mkdir -p docs/releases
[ -f "docs/releases/$VERSION.html" ] || cat > "docs/releases/$VERSION.html" <<EOF
<!DOCTYPE html><html><head><meta charset="utf-8"><style>body{font:15px/1.5 -apple-system,system-ui;padding:16px 20px;color:#222}</style></head>
<body><h2>Heron $VERSION</h2><ul><li>…</li></ul></body></html>
EOF

# The site's Download button points at the unversioned name, so every release ships both.
cp "$DMG" "$OUT/Heron.dmg"

echo
echo "Done: $DMG (and $OUT/Heron.dmg, the same file for the site's Download button)"
echo "Next: edit docs/releases/$VERSION.html, commit docs/, push, then create the GitHub release"
echo "v$VERSION with BOTH files attached, e.g.:"
echo "  gh release create v$VERSION \"$DMG\" \"$OUT/Heron.dmg\" --title \"Heron $VERSION\" --notes-file docs/releases/$VERSION.html"
