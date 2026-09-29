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

# 划词依赖「辅助功能」权限，而系统是按代码签名记住授权的：
# ad-hoc 签名每次构建都会变，导致每次重新构建后都要重新授权。
# 所以优先使用钥匙串里的开发者证书（可用 SIGN_IDENTITY 指定），找不到才退回 ad-hoc。
SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

echo "==> codesigning (identity: $SIGN_IDENTITY)"
codesign --force --deep --sign "$SIGN_IDENTITY" \
    --entitlements "Resources/bartrans.entitlements" \
    "$APP_BUNDLE"

echo "==> verifying architectures"
lipo -info "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

echo "==> done: $APP_BUNDLE"
echo "Run with: open \"$APP_BUNDLE\""
