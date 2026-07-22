#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
BUILD_DIR="$PROJECT_DIR/build"
OUTPUT_APP_DIR="$BUILD_DIR/UsageBar.app"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/usagebar-build.XXXXXX")"
APP_DIR="$STAGING_DIR/UsageBar.app"
trap 'rm -rf "$STAGING_DIR"' EXIT

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
xattr -cr "$APP_DIR"
codesign --force --deep --sign - --identifier local.codex.usagebar "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
ditto "$APP_DIR" "$OUTPUT_APP_DIR"
while IFS= read -r -d '' item; do
  for attribute in com.apple.FinderInfo com.apple.ResourceFork; do
    if xattr -p "$attribute" "$item" >/dev/null 2>&1; then
      xattr -d "$attribute" "$item"
    fi
  done
done < <(find "$OUTPUT_APP_DIR" -print0)
print "$OUTPUT_APP_DIR"
