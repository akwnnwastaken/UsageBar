#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_DIR="$PROJECT_DIR/build/UsageBar.app"
SENTINEL="$APP_DIR/Contents/Resources/usagebar-stale-sentinel"

"$PROJECT_DIR/build.sh"
touch "$SENTINEL"
"$PROJECT_DIR/build.sh"

if [[ -e "$SENTINEL" ]]; then
  print -u2 "Eski dosya ikinci derlemeden sonra uygulama paketinde kaldı"
  exit 1
fi

signature_valid=false
for attempt in 1 2 3; do
  xattr -cr "$APP_DIR"
  xattr -d com.apple.FinderInfo "$APP_DIR" 2>/dev/null || true
  xattr -d com.apple.ResourceFork "$APP_DIR" 2>/dev/null || true
  if codesign --verify --deep --strict "$APP_DIR"; then
    signature_valid=true
    break
  fi
  sleep 0.1
done

if [[ "$signature_valid" != true ]]; then
  print -u2 "Uygulama paketinin imza doğrulaması başarısız oldu"
  exit 1
fi

"$APP_DIR/Contents/MacOS/UsageBar" --self-test
print "Paketleme regresyon testi başarılı"
