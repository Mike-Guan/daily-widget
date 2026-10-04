#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
RUNTIME_APP="$PROJECT_DIR/node_modules/electron/dist/Electron.app"
RELEASE_DIR="$PROJECT_DIR/release"
STAGE_DIR="$RELEASE_DIR/dmg-staging"
APP_PATH="$STAGE_DIR/Daily Widget.app"
SIGN_IDENTITY="${MAC_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-DailyWidgetNotary}"

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -n 1)"
fi

if [[ -z "$SIGN_IDENTITY" && "${ALLOW_ADHOC_SIGNING:-0}" != "1" ]]; then
  print -u2 "No Developer ID Application certificate was found."
  print -u2 "Create one in Xcode > Settings > Accounts > Manage Certificates, then run npm run package:mac again."
  exit 2
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="-"
  DMG_PATH="$RELEASE_DIR/Daily-Widget-macOS-arm64-LOCAL-TEST.dmg"
else
  DMG_PATH="$RELEASE_DIR/Daily-Widget-macOS-arm64.dmg"
  if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    print -u2 "No valid notarytool keychain profile named '$NOTARY_PROFILE' was found."
    print -u2 "Create it once with: xcrun notarytool store-credentials '$NOTARY_PROFILE' --apple-id YOUR_APPLE_ID --team-id B3W4J793AD"
    exit 3
  fi
fi

if [[ ! -d "$RUNTIME_APP" ]]; then
  print -u2 "Electron runtime not found. Run npm install first."
  exit 1
fi

rm -rf "$STAGE_DIR"
rm -f "$DMG_PATH"
mkdir -p "$STAGE_DIR"

ditto "$RUNTIME_APP" "$APP_PATH"
mv "$APP_PATH/Contents/MacOS/Electron" "$APP_PATH/Contents/MacOS/Daily Widget"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Daily Widget" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Daily Widget" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable Daily Widget" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.guanshiyang.dailywidget" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile DailyWidget.icns" "$APP_PATH/Contents/Info.plist"
cp "$PROJECT_DIR/build/DailyWidget.icns" "$APP_PATH/Contents/Resources/DailyWidget.icns"

mkdir -p "$APP_PATH/Contents/Resources/app"
ditto "$PROJECT_DIR/src" "$APP_PATH/Contents/Resources/app/src"
cp "$PROJECT_DIR/main.js" "$PROJECT_DIR/preload.js" "$PROJECT_DIR/index.html" "$PROJECT_DIR/package.json" "$APP_PATH/Contents/Resources/app/"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$APP_PATH"
else
  node "$PROJECT_DIR/scripts/sign-mac.js" "$APP_PATH" "$SIGN_IDENTITY"
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
hdiutil create -volname "Daily Widget" -srcfolder "$STAGE_DIR" -format UDZO -ov "$DMG_PATH"

if [[ "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG_PATH"
  codesign --verify --strict --verbose=2 "$DMG_PATH"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"
  print "Created signed and notarized release: $DMG_PATH"
  exit 0
fi

print "Created local-test build (not safe for sharing): $DMG_PATH"
exit 0
