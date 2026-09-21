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

# Require a pattern inside one function's body. Fails closed the same way: a
# missing function or a missing pattern both stop the gate. Scoping to the
# function is what stops the packaged self-test, a comment or dead code from
# standing in for the production wiring.
require_present_in_function() {
  local label="$1" signature="$2" pattern="$3" body rc
  body=$(awk "/$signature/,/^    \}\$/" "$PROJECT_DIR/Sources/UsageBar/main.swift")
  if [[ -z "$body" ]]; then
    print -u2 "$label (fonksiyon bulunamadı: $signature)"
    exit 1
  fi
  print -r -- "$body" | grep -Eq -- "$pattern" && rc=0 || rc=$?
  if [[ $rc -ne 0 ]]; then
    print -u2 "$label"
    exit 1
  fi
}

# Require that, inside one function's body, the line right after the first
# line matching `line_pattern` matches `next_pattern`. Pins the *order* of two
# adjacent lines — an if/else whose branches were swapped still contains both
# lines, so presence alone cannot catch it.
require_next_line_in_function() {
  local label="$1" signature="$2" line_pattern="$3" next_pattern="$4" body next rc
  body=$(awk "/$signature/,/^    \}\$/" "$PROJECT_DIR/Sources/UsageBar/main.swift")
  if [[ -z "$body" ]]; then
    print -u2 "$label (fonksiyon bulunamadı: $signature)"
    exit 1
  fi
  next=$(print -r -- "$body" | grep -E -A1 -m1 -- "$line_pattern" | tail -n +2)
  if [[ -z "$next" ]]; then
    print -u2 "$label (satır bulunamadı: $line_pattern)"
    exit 1
  fi
  print -r -- "$next" | grep -Eq -- "$next_pattern" && rc=0 || rc=$?
  if [[ $rc -ne 0 ]]; then
    print -u2 "$label"
    print -u2 "$next"
    exit 1
  fi
}

# Scan one file for a forbidden pattern. Some rules are about what a specific
# *policy* must never see, which a whole-Sources scan cannot express.
scan_forbidden_in_file() {
  local label="$1" file="$2" pattern="$3" matches rc
  matches=$(grep -En -- "$pattern" "$PROJECT_DIR/$file") && rc=0 || rc=$?
  if [[ $rc -eq 0 ]]; then
    print -u2 "$label"
    print -u2 "$matches"
    exit 1
  elif [[ $rc -ne 1 ]]; then
    print -u2 "grep taraması başarısız oldu (exit $rc); güvenlik kapısı fail-closed"
    exit 1
  fi
}

# A finished read is applied to the provider it was launched for, never to the
# provider its result claims to be. The identity check is the first thing the
# acceptance path does: it must exist, and it must sit directly above the
# collection-policy gate -- and so above every cache and measurement write --
# because a check that runs after a write has already let the wrong provider's
# reading through.
require_present_in_function \
  "Sonuç kabulü yanlış sağlayıcıyı adlandıran sonucu reddetmiyor" \
  'private func acceptFetchedUsage\(' \
  '^        guard fetched\.name == providerName else \{ return \}$'

require_next_line_in_function \
  "Sağlayıcı kimlik denetimi toplama politikası kapısından önce gelmiyor" \
  'private func acceptFetchedUsage\(' \
  '^        guard fetched\.name == providerName else \{ return \}$' \
  '^        guard ProviderCollectionPolicy\.shouldAccept\($'

# Pausing clears the half-proven rise and nothing more of the display state;
# disconnect is the only transition allowed to forget the displayed value as
# well. A whole-file presence check cannot tell those two apart -- the pause
# path's clear and the disconnect path's forget both legitimately exist -- so
# each call is pinned to the function it belongs to.
require_present_in_function \
  "Duraklatma bekletilen yükselişi temizlemiyor" \
  'private func setCollectionEnabled' \
  'displayFilter\.clearPendingRise\('

scan_forbidden_in_function \
  "Duraklatma gösterilen değeri unutuyor" \
  'private func setCollectionEnabled' \
  'displayFilter\.forget\('

require_present_in_function \
  "Bağlantı kaldırma gösterim durumunu unutmuyor" \
  'private func disconnectProvider' \
  'displayFilter\.forget\(provider: providerName\)'

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

# --- Ayrıntı görünürlüğü ---------------------------------------------------
#
# Ayrıntı görünürlüğü yalnızca bir sunum tercihidir. Aşağıdaki kapılar, onun
# toplama yaşam döngüsüne, seçime, döndürmeye ya da menü çubuğuna sızmadığını
# ve gizli gövde kararının üretim çiziminde gerçekten uygulandığını korur.

# Denetim kanonik sunum yolundan geçer. Tercihi tıklama işleyicisinden yazmak,
# tek mutasyon noktasını atlardı.
require_present \
  "Ayrıntı denetimi kanonik sunum yolunu çağırmıyor" \
  'setDetailsVisible\(!detailsVisible\(providerName\), forProvider: providerName\)'

require_occurrences \
  "Codex ayrıntı tercihi birden fazla yerde yazılıyor" \
  'forKey: PreferenceKey\.codexDetailsVisible\)' 1

require_occurrences \
  "Claude ayrıntı tercihi birden fazla yerde yazılıyor" \
  'forKey: PreferenceKey\.claudeDetailsVisible\)' 1

# Kanonik yol yalnızca tercihi saklar ve menüyü yeniden kurar. Toplama durumu,
# nesil, bekleyen yenileme, önbellek, geçmiş, filtre, seçim ve döndürme
# tercihinin hiçbirine dokunmaz.
scan_forbidden_in_function \
  "Ayrıntı görünürlüğü toplama yaşam döngüsüne dokunuyor" \
  'private func setDetailsVisible' \
  'setCollectionEnabled|CollectionEnabled = |bumpGeneration|pendingRefreshAfterEnable|displayFilter|usageHistory|usages|refresh\(\)|selectedProviderName|autoRotateProviders'

# ... ve duraklatma da tersine ayrıntı görünürlüğünü değiştirmez.
scan_forbidden_in_function \
  "Duraklatma ayrıntı görünürlüğünü değiştiriyor" \
  'private func setCollectionEnabled' \
  'etailsVisible'

# Bağlanmak toplama durumunu geri açar ama sunum tercihi kullanıcının kalır.
scan_forbidden_in_function \
  "Codex bağlantısı ayrıntı görünürlüğünü sıfırlıyor" \
  '@objc private func connectCodex' \
  'etailsVisible'

scan_forbidden_in_function \
  "Claude bağlantısı ayrıntı görünürlüğünü sıfırlıyor" \
  '@objc private func connectClaude' \
  'etailsVisible'

scan_forbidden_in_function \
  "Bağlantı kaldırma ayrıntı görünürlüğünü sıfırlıyor" \
  'private func disconnectProvider' \
  'etailsVisible'

# Uygunluk, etkin sağlayıcı ve döndürme bu tercihi hiç görmez.
scan_forbidden_in_file \
  "Toplama politikası ayrıntı görünürlüğüne bakıyor" \
  'Sources/UsageBarCore/ProviderCollectionPolicy.swift' \
  'etailsVisible|DetailVisibility'

scan_forbidden_in_file \
  "Durum ve döndürme politikası ayrıntı görünürlüğüne bakıyor" \
  'Sources/UsageBarCore/ProviderStatusPolicy.swift' \
  'etailsVisible|DetailVisibility'

scan_forbidden_in_function \
  "Sağlayıcı toplama durumları ayrıntı görünürlüğü taşıyor" \
  'private var providerCollectionStates' \
  'etailsVisible'

scan_forbidden_in_function \
  "Etkin sağlayıcı seçimi ayrıntı görünürlüğüne bakıyor" \
  'private var statusProviderName' \
  'etailsVisible'

scan_forbidden_in_function \
  "Menü çubuğu başlığı ayrıntı görünürlüğüne bakıyor" \
  'private func updateStatusTitle' \
  'etailsVisible'

# Çalışma zamanı karar noktaları. Yukarıdaki politika dosyası taramaları
# politikanın bir görünürlük parametresi *edinmesini* engeller; bunlar ise
# politikayı çağıran üretim noktalarının o parametreye kendi başına bir
# görünürlük ifadesi eklemesini engeller — örneğin
# `collectionEnabled: codexCollectionEnabled && codexDetailsVisible`. Toplama
# planı, başlatma, sonuç kabulü, geçmiş kaydı, gösterim filtresi, uygun/bağlı
# sağlayıcı listeleri ve döndürme zamanlayıcısı bu tercihin hiçbir biçimini
# göremez: ne tercihin kendisini, ne anahtarını, ne de sunum planını.
detail_presentation_tokens='etailsVisible|DetailVisibility|details\.visible|ProviderDetailPresentationPolicy|ProviderCardPlan|showsDetailBody'

scan_forbidden_in_function \
  "Yenileme planı ayrıntı görünürlüğüne bakıyor" \
  '@objc private func refresh\(\)' \
  "$detail_presentation_tokens"

scan_forbidden_in_function \
  "Sağlayıcı başlatma ayrıntı görünürlüğüne bakıyor" \
  'private func launch\(' \
  "$detail_presentation_tokens"

scan_forbidden_in_function \
  "Sonuç kabulü ayrıntı görünürlüğüne bakıyor" \
  'private func acceptFetchedUsage\(' \
  "$detail_presentation_tokens"

scan_forbidden_in_function \
  "Geçmiş kaydı ayrıntı görünürlüğüne bakıyor" \
  'private func recordUsageHistory\(' \
  "$detail_presentation_tokens"

scan_forbidden_in_function \
  "Saklama bakımı ayrıntı görünürlüğüne bakıyor" \
  'private func maintainUsageHistoryRetention\(' \
  "$detail_presentation_tokens"

scan_forbidden_in_function \
  "Gösterim filtresi ilerletmesi ayrıntı görünürlüğüne bakıyor" \
  'private func advanceDisplayedRemaining\(' \
  "$detail_presentation_tokens"

scan_forbidden_in_function \
  "Gösterilen okumalar ayrıntı görünürlüğüne bakıyor" \
  'private var displayUsages' \
  "$detail_presentation_tokens"

scan_forbidden_in_function \
  "Bağlı sağlayıcı listesi ayrıntı görünürlüğüne bakıyor" \
  'private var connectedProviderNames' \
  "$detail_presentation_tokens"

scan_forbidden_in_function \
  "Uygun sağlayıcı listesi ayrıntı görünürlüğüne bakıyor" \
  'private var eligibleProviderNames' \
  "$detail_presentation_tokens"

scan_forbidden_in_function \
  "Döndürme zamanlayıcısı ayrıntı görünürlüğüne bakıyor" \
  'private func configureStatusPresentationTimer\(' \
  "$detail_presentation_tokens"

# Uygun sağlayıcı listesi politikanın verdiği listenin *kendisidir*; ona
# eklenen bir süzgeç, hangi ölçütle olursa olsun, bir sağlayıcıyı sessizce
# menü çubuğundan ve döndürmeden düşürür.
require_present_in_function \
  "Uygun sağlayıcı listesi politikadan olduğu gibi alınmıyor" \
  'private var eligibleProviderNames' \
  '^        ProviderStatusPolicy\.eligibleNames\(providerCollectionStates\)$'

scan_forbidden_in_function \
  "Uygun sağlayıcı listesi süzülüyor" \
  'private var eligibleProviderNames' \
  '\.filter|\.compactMap|\.first|\.prefix|\.dropFirst|\.removeAll'

# Her ayrıntı denetimi kendi sağlayıcısını değiştirir. Kalıplar işleyicinin
# tamamını yakalar — adını, çağırdığı yolu ve verdiği sağlayıcı adını — bu
# yüzden iki adın dosyada bir yerlerde geçmesi yetmez: Codex işleyicisi Claude'a
# yönlenirse, ya da ikisi aynı sağlayıcıya giderse, satırın biri kaybolur.
require_occurrences \
  "Codex ayrıntı denetimi kendi sağlayıcısına yönlenmiyor" \
  '@objc private func toggleCodexDetails\(\) \{ toggleDetailsVisible\(for: "Codex"\) \}' 1

require_occurrences \
  "Claude ayrıntı denetimi kendi sağlayıcısına yönlenmiyor" \
  '@objc private func toggleClaudeDetails\(\) \{ toggleDetailsVisible\(for: "Claude Code"\) \}' 1

# ... ve toplama denetimleri için de aynı bağ geçerlidir; ayrıntı denetimi
# onların yanına eklendiği için ikisi birlikte sabitlenir.
require_occurrences \
  "Codex toplama denetimi kendi sağlayıcısına yönlenmiyor" \
  '@objc private func toggleCodexCollection\(\) \{ toggleCollection\(for: "Codex"\) \}' 1

require_occurrences \
  "Claude toplama denetimi kendi sağlayıcısına yönlenmiyor" \
  '@objc private func toggleClaudeCollection\(\) \{ toggleCollection\(for: "Claude Code"\) \}' 1

# Kanonik yol da doğru alanı yazar: Codex dalı Codex tercihini, Claude dalı
# Claude tercihini. Her dal tek satırdır, bu yüzden dalın başlığından hemen
# sonraki satır sabitlenir — iki atamanın yer değiştirmesi ikisini de bozar.
require_next_line_in_function \
  "Ayrıntı ayarlayıcısı Codex dalında Codex tercihini yazmıyor" \
  'private func setDetailsVisible' \
  '^        if providerName == "Codex" \{$' \
  '^            codexDetailsVisible = visible$'

require_next_line_in_function \
  "Ayrıntı ayarlayıcısı Claude dalında Claude tercihini yazmıyor" \
  'private func setDetailsVisible' \
  '^        \} else \{$' \
  '^            claudeDetailsVisible = visible$'

# Sağlayıcı yönetimi satırı denetimi taşır, tercihi kendisi yazmaz ve toplama
# durumuna dokunmaz. "Ayrıntıları göster" gizlediği gövdenin dışında durur.
require_present_in_function \
  "Ayrıntı denetimi sağlayıcı yönetimine eklenmiyor" \
  'private func addProviderManagementItems' \
  'title: text\.showDetails'

require_present_in_function \
  "Ayrıntı denetimi saklanan tercihi yansıtmıyor" \
  'private func addProviderManagementItems' \
  'detailsItem\.state = detailsVisible\(providerName\) \? \.on : \.off'

scan_forbidden_in_function \
  "Sağlayıcı yönetimi tercihi doğrudan yazıyor ya da toplamayı değiştiriyor" \
  'private func addProviderManagementItems' \
  'UserDefaults|setCollectionEnabled|setDetailsVisible'

# Kart, canlı tercihten kurulan sunum planına göre çizilir ve kullanım
# pencereleri yalnızca o plandan geçen listeden sayılır: gizli gövdede tek bir
# kullanım satırı, sıfırlanma satırı, geçmiş özeti ya da grafik kalamaz.
require_present \
  "Kart canlı ayrıntı tercihiyle kurulmuyor" \
  'detailsVisible: detailsVisible\(providerName\)'

require_present_in_function \
  "Sağlayıcı kartı sunum planından kurulmuyor" \
  'private func addProvider\(_ usage' \
  'ProviderDetailPresentationPolicy\.card\('

require_present_in_function \
  "Ayrıntı gövdesi tek bir kapıdan geçmiyor" \
  'private func addProvider\(_ usage' \
  'let detailWindows = plan\.showsDetailBody \? usage\.windows : \[\]'

scan_forbidden_in_function \
  "Kullanım pencereleri kapıdan geçmeyen bir listeden sayılıyor" \
  'private func addProvider\(_ usage' \
  'usage\.windows\.enumerated\(\)'

require_present_in_function \
  "Etkin hata satırı sunum planından geçmiyor" \
  'private func addProvider\(_ usage' \
  'plan\.showsOperationalIssue'

# Duraklatma işareti de plandan gelir, böylece gizli kartta da yerinde kalır.
require_present_in_function \
  "Duraklatma işareti sunum planından gelmiyor" \
  'private func addProvider\(_ usage' \
  'plan\.showsPausedMarker \?'

# --- Menü açılır bölümü --------------------------------------------------
#
# Menünün alt denetimlerini açıp kapayan durum yalnızca oturum içi bir sunum
# durumudur. Aşağıdaki kapılar onun saklanmadığını, yalnızca kendi denetiminden
# değiştiğini, olağan menü kurulumlarının onu sıfırlamadığını ve hiçbir
# sağlayıcı kararına sızmadığını korur; ayrıca eski alttaki "Çık" satırının
# geri gelmediğini ve sağ üstteki simgenin gerçekten uygulamadan çıktığını
# sabitler.
menu_disclosure_tokens='menuDisclosure|MenuDisclosureState|revealsLowerControls|chevronSymbolName'

# Durum tek bir yerde kurulur, tek bir yerde değişir ve hiçbir yerde saklanmaz.
require_occurrences \
  "Menü açılır durumu tek bir üye olarak kurulmuyor" \
  'private var menuDisclosure = MenuDisclosureState\(\)' 1

require_occurrences \
  "Menü açılır durumu yalnızca kendi denetiminden değişmiyor" \
  'menuDisclosure\.toggle\(\)' 1

require_present_in_function \
  "Açılır denetim durumu değiştirmiyor" \
  '@objc private func toggleMenuDisclosure\(\)' \
  'menuDisclosure\.toggle\(\)'

scan_forbidden \
  "Menü açılır durumu yeniden atanıyor" \
  '(self\.|^[[:space:]]*)menuDisclosure = '

scan_forbidden_in_file \
  "Menü açılır durumu UserDefaults'a yazılıyor" \
  'Sources/UsageBarCore/MenuDisclosure.swift' \
  'UserDefaults[.(]|forKey:'

scan_forbidden_in_function \
  "Menü kurulumu açılır durumunu sıfırlıyor" \
  'private func rebuildMenu\(\)' \
  'MenuDisclosureState\(|\.toggle\('

# Kurulum bellekteki durumu okur ve alt bölümü yalnızca o açıkken kurar; dil
# değişimi, yenileme ve diğer olağan kurulumlar aynı yoldan geçer. Denetim ise
# durumu çevirip aynı kurulumu çağırır.
require_present_in_function \
  "Menü kurulumu alt bölümü açılır durumuna göre kurmuyor" \
  'private func rebuildMenu\(\)' \
  '^        guard menuDisclosure\.revealsLowerControls else \{ return \}$'

require_next_line_in_function \
  "Açılır denetim durumu çevirdikten sonra menüyü yeniden kurmuyor" \
  '@objc private func toggleMenuDisclosure\(\)' \
  '^        menuDisclosure\.toggle\(\)$' \
  '^        rebuildMenu\(\)$'

# Alttaki metin satırı "Çık" artık üretilmez; sağ üstteki simge mevcut çıkış
# eylemine bağlıdır ve o eylem hâlâ uygulamayı sonlandırır.
scan_forbidden \
  "Alttaki metin satırı Çık öğesi hâlâ üretiliyor" \
  'NSMenuItem\(title: text\.quit'

require_present_in_function \
  "Sağ üst çıkış simgesi mevcut çıkış eylemine bağlı değil" \
  'private func addQuitHeader\(\)' \
  'action: #selector\(quit\)'

require_present_in_function \
  "Sağ üst çıkış simgesi erişilebilirlik etiketi taşımıyor" \
  'private func addQuitHeader\(\)' \
  'label: text\.quit'

require_present_in_function \
  "Çıkış eylemi uygulamayı sonlandırmıyor" \
  '@objc private func quit\(\)' \
  'NSApp\.terminate\(nil\)'

# Sağlayıcı kartı ve bağlantı satırları açılır bölümün dışında, ondan
# bağımsız kurulur.
scan_forbidden_in_function \
  "Sağlayıcı kartı açılır durumuna bakıyor" \
  'private func addProvider\(_ usage' \
  "$menu_disclosure_tokens"

scan_forbidden_in_function \
  "Bağlantı satırı açılır durumuna bakıyor" \
  'private func addConnectionItem\(' \
  "$menu_disclosure_tokens"

# Politikalar ve çalışma zamanı karar noktaları bu durumu hiç görmez.
scan_forbidden_in_file \
  "Toplama politikası menü açılır durumuna bakıyor" \
  'Sources/UsageBarCore/ProviderCollectionPolicy.swift' \
  "$menu_disclosure_tokens|isExpanded"

scan_forbidden_in_file \
  "Durum ve döndürme politikası menü açılır durumuna bakıyor" \
  'Sources/UsageBarCore/ProviderStatusPolicy.swift' \
  "$menu_disclosure_tokens|isExpanded"

scan_forbidden_in_file \
  "Ayrıntı sunum politikası menü açılır durumuna bakıyor" \
  'Sources/UsageBarCore/ProviderDetailVisibility.swift' \
  "$menu_disclosure_tokens|isExpanded"

for signature in \
  '@objc private func refresh\(\)' \
  'private func launch\(' \
  'private func acceptFetchedUsage\(' \
  'private func recordUsageHistory\(' \
  'private func maintainUsageHistoryRetention\(' \
  'private func advanceDisplayedRemaining\(' \
  'private var displayUsages' \
  'private var connectedProviderNames' \
  'private var eligibleProviderNames' \
  'private var providerCollectionStates' \
  'private var statusProviderName' \
  'private func configureStatusPresentationTimer\(' \
  'private func updateStatusTitle' \
  'private func setCollectionEnabled' \
  'private func setDetailsVisible' \
  'private func disconnectProvider'
do
  scan_forbidden_in_function \
    "Karar noktası menü açılır durumuna bakıyor: $signature" \
    "$signature" \
    "$menu_disclosure_tokens"
done

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
