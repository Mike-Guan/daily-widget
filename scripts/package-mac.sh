#!/bin/zsh

set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
RUNTIME_APP="$PROJECT_DIR/node_modules/electron/dist/Electron.app"
RELEASE_DIR="$PROJECT_DIR/release"
STAGE_DIR="$RELEASE_DIR/dmg-staging"
APP_PATH="$STAGE_DIR/Daily Widget.app"
DMG_PATH="$RELEASE_DIR/Daily-Widget-macOS-arm64.dmg"

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
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.guanshiyang.dailywidget.mac" "$APP_PATH/Contents/Info.plist"

mkdir -p "$APP_PATH/Contents/Resources/app"
ditto "$PROJECT_DIR/src" "$APP_PATH/Contents/Resources/app/src"
cp "$PROJECT_DIR/main.js" "$PROJECT_DIR/preload.js" "$PROJECT_DIR/index.html" "$PROJECT_DIR/package.json" "$APP_PATH/Contents/Resources/app/"

codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
if hdiutil create -volname "Daily Widget" -srcfolder "$STAGE_DIR" -format UDZO -ov "$DMG_PATH"; then
  print "Created $DMG_PATH"
  exit 0
fi

ZIP_PATH="$RELEASE_DIR/Daily-Widget-macOS-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"
print -u2 "DMG creation is unavailable in this environment. Created $ZIP_PATH instead. Run this script from a normal macOS Terminal to create the DMG."
