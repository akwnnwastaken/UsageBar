#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
BUILD_DIR="$PROJECT_DIR/build"
APP_DIR="$BUILD_DIR/UsageBar.app"

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
mkdir -p "$BUILD_DIR/module-cache"

CLANG_MODULE_CACHE_PATH="$BUILD_DIR/module-cache" \
SWIFT_MODULECACHE_PATH="$BUILD_DIR/module-cache" \
xcrun swiftc \
  -swift-version 5 \
  -O \
  -framework AppKit \
  -framework Foundation \
  "$PROJECT_DIR/Sources/UsageBar/main.swift" \
  -o "$APP_DIR/Contents/MacOS/UsageBar"

cp "$PROJECT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

"$APP_DIR/Contents/MacOS/UsageBar" --self-test
print "$APP_DIR"
