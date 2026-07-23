#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"

if rg -n 'readDataToEndOfFile|/usr/bin/jq' "$PROJECT_DIR/Sources"; then
  print -u2 "Yasaklı veya yarışa açık çıktı okuma kalıbı bulundu"
  exit 1
fi

if rg -n 'ProcessInfo\.processInfo\.environment\[[^]]*(TOKEN|KEY|SECRET|PASSWORD)' \
  "$PROJECT_DIR/Sources"; then
  print -u2 "Sağlayıcı ortamına hassas değişken aktarımı bulundu"
  exit 1
fi

"$PROJECT_DIR/tests/build_regression.sh"
git -C "$PROJECT_DIR" diff --check
print "Güvenlik kabul testleri başarılı"
