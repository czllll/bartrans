#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="bartrans"
UNIVERSAL_BIN=".build/apple/Products/Release/$APP_NAME"
APP_BUNDLE=".build/release/$APP_NAME.app"

echo "==> swift build -c release (universal: arm64 + x86_64)"
swift build -c release --arch arm64 --arch x86_64

echo "==> assembling $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$UNIVERSAL_BIN" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

echo "==> codesigning (ad-hoc, with entitlements)"
codesign --force --deep --sign - \
    --entitlements "Resources/bartrans.entitlements" \
    "$APP_BUNDLE"

echo "==> verifying architectures"
lipo -info "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

echo "==> done: $APP_BUNDLE"
echo "Run with: open \"$APP_BUNDLE\""
