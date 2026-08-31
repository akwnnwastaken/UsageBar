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

# Require a pattern to be present. Absence means the production wiring it stands
# for is gone, so this fails closed exactly like the forbidden scans: any exit
# status other than "match found" (0) stops the gate.
require_present() {
  local label="$1" pattern="$2" rc
  grep -rEq -- "$pattern" "$PROJECT_DIR/Sources" && rc=0 || rc=$?
  if [[ $rc -ne 0 ]]; then
    print -u2 "$label"
    exit 1
  fi
}

# Count how many times a pattern occurs across Sources. Used for call sites
# whose number is part of the contract, not just their presence.
require_occurrences() {
  local label="$1" pattern="$2" expected="$3" count
  count=$({ grep -rEo -- "$pattern" "$PROJECT_DIR/Sources" || true; } | wc -l | tr -d ' ')
  if [[ "$count" != "$expected" ]]; then
    print -u2 "$label (bulunan: $count, beklenen: $expected)"
    exit 1
  fi
}

# Collection gating. These assert the shape of the wiring, not its layout: the
# pure policy in UsageBarCore is what proves the rules themselves.
#
# Each pattern names state only the running application has. A bare
# `ProviderCollectionPolicy.…(` would also be satisfied by the packaged
# self-test's own assertions, which would leave the production call sites
# unguarded.
require_present \
  "Codex başlatma kararı canlı toplama durumundan okunmuyor" \
  'connected: codexConnected'

require_present \
  "Claude başlatma kararı canlı toplama durumundan okunmuyor" \
  'connected: claudeConnected'

require_present \
  "Boş toplama turu politikadan geçmiyor" \
  'ProviderCollectionPolicy\.collectsUsage\(plan'

require_present \
  "Sonuç kabulü sağlayıcının güncel neslinden geçmiyor" \
  'currentGeneration: generation\(of: providerName\)'

# Two call sites: the empty collection cycle and switching usage history back
# on. Both must keep pruning without creating a sample.
require_occurrences \
  "Saklama bakımı çağrı noktası sayısı beklenenden farklı" \
  'maintainUsageHistoryRetention\(at:' 2

# One launch site per provider, each behind the gate above. A second one would
# be a path that never consulted the policy.
require_occurrences \
  "Codex toplama başlatma noktası sayısı beklenenden farklı" \
  'codexFetcher\.fetch' 1

require_occurrences \
  "Claude toplama başlatma noktası sayısı beklenenden farklı" \
  'claudeFetcher\.fetch' 1

# The display filter and the history recorder may only see measurements this
# cycle accepted. These are the two whole-cache shapes that used to feed them.
scan_forbidden \
  "Gösterim filtresi önbelleğin tamamından ilerletiliyor" \
  'for \(providerName, usage\) in usages'

scan_forbidden \
  "Geçmiş kaydı bağlı sağlayıcıların önbelleğinden besleniyor" \
  'for providerName in connectedProviderNames'

# ... and neither may be handed the cache directly.
scan_forbidden \
  "Ölçüm tüketicilerine önbelleğin tamamı veriliyor" \
  '(advanceDisplayedRemaining\(with:|recordUsageHistory\(of:) (self\.)?usages'

# Pausing clears the half-proven rise; disconnect is the only thing allowed to
# forget the displayed value as well.
require_present \
  "Duraklatma bekletilen yükselişi temizlemiyor" \
  'displayFilter\.clearPendingRise\('

# The pause/resume control goes through the one runtime mutation path. Writing
# the preference from the click handler would skip the generation bump, the
# pending-rise clearing and the coalesced refresh.
require_present \
  "Toplama denetimi kanonik çalışma zamanı yolunu çağırmıyor" \
  'setCollectionEnabled\(!collectionEnabled\(providerName\), forProvider: providerName\)'

require_occurrences \
  "Codex toplama tercihi birden fazla yerde yazılıyor" \
  'forKey: PreferenceKey\.codexCollectionEnabled\)' 1

require_occurrences \
  "Claude toplama tercihi birden fazla yerde yazılıyor" \
  'forKey: PreferenceKey\.claudeCollectionEnabled\)' 1

# Scan one function's body for a forbidden pattern. Some rules are about what a
# specific transition must NOT touch, and a whole-file scan cannot express that.
scan_forbidden_in_function() {
  local label="$1" signature="$2" pattern="$3" body matches rc
  body=$(awk "/$signature/,/^    \}\$/" "$PROJECT_DIR/Sources/UsageBar/main.swift")
  if [[ -z "$body" ]]; then
    print -u2 "$label (fonksiyon bulunamadı: $signature)"
    exit 1
  fi
  matches=$(print -r -- "$body" | grep -En -- "$pattern") && rc=0 || rc=$?
  if [[ $rc -eq 0 ]]; then
    print -u2 "$label"
    print -u2 "$matches"
    exit 1
  elif [[ $rc -ne 1 ]]; then
    print -u2 "grep taraması başarısız oldu (exit $rc); güvenlik kapısı fail-closed"
    exit 1
  fi
}

# Pausing is not a selection change and not a rotation change: the stored
# preferences must survive it untouched, so resuming restores what the user
# chose. Disconnect keeps its own separate repair rules.
scan_forbidden_in_function \
  "Duraklatma saklanan sağlayıcı seçimini değiştiriyor" \
  'private func setCollectionEnabled' \
  'selectedProviderName'

scan_forbidden_in_function \
  "Duraklatma otomatik döndürme tercihini değiştiriyor" \
  'private func setCollectionEnabled' \
  'autoRotateProviders'

# Etkin sağlayıcı ve döndürme yalnızca toplama yapan sağlayıcılardan seçilir.
require_present \
  "Etkin sağlayıcı toplama yapanlardan seçilmiyor" \
  'eligible: eligibleProviderNames'

require_present \
  "Döndürme adayları toplama yapanlardan alınmıyor" \
  'eligibleCount: eligibleProviderNames\.count'

scan_forbidden \
  "Döndürme hâlâ bağlı sağlayıcı sayısına bakıyor" \
  'autoRotateProviders && connectedProviderNames\.count > 1'

# Sağlayıcı seçici ve yönetim satırları bağlı sağlayıcılardan kurulur; seçicinin
# tıklama işleyicisi listeyi yeniden hesaplamaz, kurulduğu eşlemeyi okur.
require_present \
  "Sağlayıcı yönetimi bağlı sağlayıcı listesinden kurulmuyor" \
  'addProviderManagementItems\(connectedNames\)'

require_present \
  "Seçici tıklaması yakalanan sağlayıcı eşlemesini kullanmıyor" \
  'let providerNames = selectorProviderNames'

# "Hepsi duraklatıldı", "önce bağlayın" ile karıştırılmaz.
require_present \
  "Boşta kalma nedeni bağlı/toplayan ayrımından hesaplanmıyor" \
  'connectedCount: connectedProviderNames\.count'

require_present \
  "Hepsi duraklatıldı durumu duraklatma metnini göstermiyor" \
  'text\.collectionPaused'

# Teşhis, bağlantı ve toplama durumunu ayrı ayrı bildirir; toplama durumu
# politikadan türetilir, bağlantıdan ya da önbellekten değil.
require_present \
  "Teşhis toplama durumunu ayrı bildirmiyor" \
  'connected:\\\(connected\),collecting:\\\(collecting\)'

require_present \
  "Teşhis toplama durumu toplama politikasından türetilmiyor" \
  'let collecting = ProviderCollectionPolicy\.isEligible\('

"$PROJECT_DIR/tests/build_regression.sh"
git -C "$PROJECT_DIR" diff --check
print "Güvenlik kabul testleri başarılı"
