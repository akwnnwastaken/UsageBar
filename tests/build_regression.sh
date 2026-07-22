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

codesign --verify --deep --strict "$APP_DIR"
"$APP_DIR/Contents/MacOS/UsageBar" --self-test
print "Paketleme regresyon testi başarılı"
