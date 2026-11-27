#!/bin/bash
# Next ship (this Mac already has Developer ID + Keychain profile umpadumpa-notary):
#   ./scripts/distribute-macos.sh
# Send: build/distribute/UmpaDumpa.zip
# Recipient: unzip, drag UmpaDumpa.app into Applications, set mysql/mysqldump in Settings.
# First-time only: Xcode certificate "Developer ID Application", then
#   xcrun notarytool store-credentials umpadumpa-notary --apple-id EMAIL --team-id 3N673T64VD

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
XCODE="/Applications/Xcode.app/Contents/Developer"
export DEVELOPER_DIR="$XCODE"
XB="$XCODE/usr/bin/xcodebuild"

SCHEME="umpadumpa"
TEAM="3N673T64VD"
NOTARY_PROFILE="${NOTARY_PROFILE:-umpadumpa-notary}"

BUILD_DIR="$ROOT/build/distribute"
ARCHIVE="$BUILD_DIR/UmpaDumpa.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
ZIP="$BUILD_DIR/UmpaDumpa.zip"
EXPORT_OPTIONS="$ROOT/scripts/exportOptions-developer-id.plist"

echo "=== 1. Developer ID certificate ==="
IDENTITIES="$(security find-identity -v -p codesigning | grep "Developer ID Application" || true)"
if [ -z "$IDENTITIES" ]; then
  echo ""
  echo "No Developer ID Application certificate on this Mac yet."
  echo "Create it once (needs the Alfa Communication Apple Developer login):"
  echo "  1. Open Xcode"
  echo "  2. Xcode > Settings > Accounts"
  echo "  3. Select the team (3N673T64VD)"
  echo "  4. Manage Certificates > + > Developer ID Application"
  echo "Then run this script again."
  exit 1
fi
echo "$IDENTITIES"

mkdir -p "$BUILD_DIR"

echo ""
echo "=== 2. Archive Release for macOS ==="
"$XB" \
  -project "$ROOT/umpadumpa.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE" \
  archive \
  DEVELOPMENT_TEAM="$TEAM"

echo ""
echo "=== 3. Export Developer ID app ==="
rm -rf "$EXPORT_DIR"
"$XB" -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT_DIR" \
  -exportOptionsPlist "$EXPORT_OPTIONS"

APP="$EXPORT_DIR/UmpaDumpa.app"
if [ ! -d "$APP" ]; then
  echo "Export did not produce UmpaDumpa.app"
  ls -la "$EXPORT_DIR" || true
  exit 1
fi

echo ""
echo "=== 4. Zip (keeps the .app bundle intact) ==="
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Zip: $ZIP"

echo ""
echo "=== 5. Notarize ==="
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "Notary keychain profile '$NOTARY_PROFILE' is not set up yet."
  echo "One-time setup (use an app-specific password from appleid.apple.com):"
  echo "  xcrun notarytool store-credentials $NOTARY_PROFILE --apple-id YOUR_APPLE_ID --team-id $TEAM"
  echo ""
  echo "The zip is ready to send only after notarization. Do not email this zip yet."
  echo "After store-credentials, run this script again."
  exit 1
fi

xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo ""
echo "Done. Send this file:"
echo "  $ZIP"
echo "The other person unzips and drags UmpaDumpa.app into Applications."
echo "They still need mysql/mysqldump on their Mac (Settings paths)."
