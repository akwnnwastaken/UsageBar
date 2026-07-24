#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"

# The forbidden-pattern scans below must fail closed. The previous form,
# `if rg -n PATTERN; then fail; fi`, silently passed whenever the scanner could
# not run: a missing or erroring command exits non-zero, which the `if` reads as
# "no match". And `rg` is not guaranteed to exist -- on some setups it is only an
# interactive shell function, absent in this non-interactive script -- so those
# scans were being skipped entirely. Use `grep`, which POSIX guarantees, and
# treat any exit status other than the clean "no match" code (1) as a hard
# failure.
if ! command -v grep >/dev/null 2>&1; then
  print -u2 "grep bulunamadı; güvenlik kabul kapısı fail-closed olarak durduruldu"
  exit 1
fi

# Scan Sources for a forbidden pattern. grep exit 0 = match found (forbidden,
# fail); 1 = no match (ok); anything else = scan error (fail closed).
scan_forbidden() {
  local label="$1" pattern="$2" matches rc
  matches=$(grep -rEn -- "$pattern" "$PROJECT_DIR/Sources") && rc=0 || rc=$?
  if [[ $rc -eq 0 ]]; then
    print -u2 "$label"
    print -u2 "$matches"
    exit 1
  elif [[ $rc -ne 1 ]]; then
    print -u2 "grep taraması başarısız oldu (exit $rc); güvenlik kapısı fail-closed"
    exit 1
  fi
}

scan_forbidden \
  "Yasaklı veya yarışa açık çıktı okuma kalıbı bulundu" \
  'readDataToEndOfFile|/usr/bin/jq'

scan_forbidden \
  "Sağlayıcı ortamına hassas değişken aktarımı bulundu" \
  'ProcessInfo\.processInfo\.environment\[[^]]*(TOKEN|KEY|SECRET|PASSWORD)'

"$PROJECT_DIR/tests/build_regression.sh"
git -C "$PROJECT_DIR" diff --check
print "Güvenlik kabul testleri başarılı"
