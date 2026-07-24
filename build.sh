#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h}"
BUILD_DIR="$PROJECT_DIR/build"
OUTPUT_APP_DIR="$BUILD_DIR/UsageBar.app"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/usagebar-build.XXXXXX")"
APP_DIR="$STAGING_DIR/UsageBar.app"
mkdir -p "$BUILD_DIR/module-cache"
PUBLISH_DIR="$(mktemp -d "$BUILD_DIR/.usagebar-publish.XXXXXX")"
PUBLISH_APP_DIR="$PUBLISH_DIR/UsageBar.app"
BACKUP_APP_DIR="$PUBLISH_DIR/Previous.app"

cleanup() {
  rm -rf "$STAGING_DIR" "$PUBLISH_DIR"
}

remove_signature_detritus() {
  local bundle="$1"
  xattr -cr "$bundle"
  while IFS= read -r -d '' item; do
    xattr -d com.apple.FinderInfo "$item" 2>/dev/null || true
    xattr -d com.apple.ResourceFork "$item" 2>/dev/null || true
  done < <(find "$bundle" -print0)
  # Traversing a File Provider folder can recreate an empty FinderInfo on the
  # bundle root, so clean that root once more immediately before verification.
  xattr -d com.apple.FinderInfo "$bundle" 2>/dev/null || true
  xattr -d com.apple.ResourceFork "$bundle" 2>/dev/null || true
}

verify_published_signature() {
  local bundle="$1"
  local attempt
  for attempt in 1 2 3; do
    remove_signature_detritus "$bundle"
    if codesign --verify --deep --strict "$bundle"; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}
trap cleanup EXIT

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

SWIFTPM_BUILD_DIR="$BUILD_DIR/swiftpm"
CLANG_MODULE_CACHE_PATH="$BUILD_DIR/module-cache" \
SWIFT_MODULECACHE_PATH="$BUILD_DIR/module-cache" \
swift test \
  --package-path "$PROJECT_DIR" \
  --scratch-path "$SWIFTPM_BUILD_DIR"

CLANG_MODULE_CACHE_PATH="$BUILD_DIR/module-cache" \
SWIFT_MODULECACHE_PATH="$BUILD_DIR/module-cache" \
swift build \
  --package-path "$PROJECT_DIR" \
  --scratch-path "$SWIFTPM_BUILD_DIR" \
  --configuration release

SWIFTPM_BINARY_DIR="$(swift build \
  --package-path "$PROJECT_DIR" \
  --scratch-path "$SWIFTPM_BUILD_DIR" \
  --configuration release \
  --show-bin-path)"
cp "$SWIFTPM_BINARY_DIR/UsageBar" "$APP_DIR/Contents/MacOS/UsageBar"

cp "$PROJECT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/UsageBar.icns" "$APP_DIR/Contents/Resources/UsageBar.icns"

"$APP_DIR/Contents/MacOS/UsageBar" --self-test
xattr -cr "$APP_DIR"
codesign --force --sign - --identifier local.codex.usagebar "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

# Publish from a clean directory. Copying into an existing .app would preserve
# stale files from an earlier build and invalidate the final code signature.
ditto "$APP_DIR" "$PUBLISH_APP_DIR"
verify_published_signature "$PUBLISH_APP_DIR"

if [[ -e "$OUTPUT_APP_DIR" ]]; then
  mv "$OUTPUT_APP_DIR" "$BACKUP_APP_DIR"
fi

if ! mv "$PUBLISH_APP_DIR" "$OUTPUT_APP_DIR"; then
  if [[ -e "$BACKUP_APP_DIR" ]]; then
    mv "$BACKUP_APP_DIR" "$OUTPUT_APP_DIR"
  fi
  exit 1
fi

if ! verify_published_signature "$OUTPUT_APP_DIR"; then
  rm -rf "$OUTPUT_APP_DIR"
  if [[ -e "$BACKUP_APP_DIR" ]]; then
    mv "$BACKUP_APP_DIR" "$OUTPUT_APP_DIR"
  fi
  exit 1
fi

print "$OUTPUT_APP_DIR"
