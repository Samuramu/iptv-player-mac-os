#!/bin/bash
# Builds a Release StreamVue.app and packages it into a drag-to-Applications DMG.
#
# Usage: scripts/build-dmg.sh [--sign "Developer ID Application: Name (TEAMID)"] [--notarize]
#
# Without --sign the app keeps its automatic (Apple Development) signature, which runs
# on this Mac; other Macs will need right-click → Open the first time (Gatekeeper).
# With a Developer ID identity plus --notarize the DMG opens cleanly everywhere.
# Notarization uses the App Store Connect API key from ~/.private_keys.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="StreamVue"
SCHEME="StreamVue"
PROJECT="StreamVue.xcodeproj"
DIST="dist"
SIGN_IDENTITY=""
NOTARIZE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sign) SIGN_IDENTITY="$2"; shift 2 ;;
    --notarize) NOTARIZE=1; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

VERSION=$(sed -n 's/.*MARKETING_VERSION = \([^;]*\);.*/\1/p' "$PROJECT/project.pbxproj" | head -1)
DMG_NAME="${APP_NAME}-${VERSION}.dmg"

echo "▶ Building ${APP_NAME} ${VERSION} (Release)…"
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release build \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true

BUILD_DIR=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR =/ { print $3 }')
APP_PATH="$BUILD_DIR/${APP_NAME}.app"
[[ -d "$APP_PATH" ]] || { echo "✗ App not found at $APP_PATH"; exit 1; }

if [[ -n "$SIGN_IDENTITY" ]]; then
  echo "▶ Signing with: $SIGN_IDENTITY"
  # Sign nested frameworks first, then the app bundle.
  find "$APP_PATH/Contents/Frameworks" -depth \( -name "*.framework" -o -name "*.dylib" \) 2>/dev/null \
    | while read -r item; do
        codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$item"
      done
  codesign --force --options runtime --timestamp \
    --entitlements "${APP_NAME}/${APP_NAME}.entitlements" \
    --sign "$SIGN_IDENTITY" "$APP_PATH"
fi
codesign --verify --deep --strict "$APP_PATH" && echo "✓ Signature valid"

echo "▶ Creating DMG…"
rm -rf "$DIST"; mkdir -p "$DIST"
STAGING=$(mktemp -d)
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO \
  "$DIST/$DMG_NAME" > /dev/null
rm -rf "$STAGING"

if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DIST/$DMG_NAME"
fi

if [[ $NOTARIZE -eq 1 ]]; then
  echo "▶ Notarizing…"
  xcrun notarytool submit "$DIST/$DMG_NAME" \
    --key ~/.private_keys/AuthKey_88TV8Y5S73.p8 \
    --key-id 88TV8Y5S73 \
    --issuer 69a6de71-fe57-47e3-e053-5b8c7c11a4d1 \
    --wait
  xcrun stapler staple "$DIST/$DMG_NAME"
fi

echo "✓ Installer ready: $DIST/$DMG_NAME ($(du -h "$DIST/$DMG_NAME" | cut -f1))"
