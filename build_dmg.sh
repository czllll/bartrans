#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="bartrans"
BUILD_DIR=".build/release"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
STAGING_DIR="$BUILD_DIR/dmg-staging"
DMG_PATH="$BUILD_DIR/$APP_NAME-macOS.dmg"
VOLUME_NAME="bartrans"

./build_app.sh

echo "==> staging DMG contents"
rm -rf "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$STAGING_DIR"
cp -R "$APP_BUNDLE" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> creating $DMG_PATH"
hdiutil create -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov -format UDZO \
    "$DMG_PATH"

rm -rf "$STAGING_DIR"

echo "==> done: $DMG_PATH"
echo "Open with: open \"$DMG_PATH\""
