#!/bin/bash
# 重新生成 Resources/AppIcon.icns 与 landing 页用的 icon.png。
# 图标本身由 Sources/bartrans/Views/BarTransLogo.swift 里的 BarTransIcon 矢量绘制。
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/AppIcon.iconset"

swiftc -parse-as-library -O -target "$(uname -m)-apple-macosx15.0" \
    -o "$WORK/render_icon" \
    scripts/render_icon.swift Sources/bartrans/Views/BarTransLogo.swift
"$WORK/render_icon" "$WORK/AppIcon.iconset"

iconutil -c icns "$WORK/AppIcon.iconset" -o Resources/AppIcon.icns
cp "$WORK/AppIcon.iconset/icon_256x256.png" landing/icon.png
cp "$WORK/AppIcon.iconset/icon_256x256.png" landing/dist/icon.png
echo "==> Resources/AppIcon.icns, landing/icon.png updated"
