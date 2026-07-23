# Security Policy / Güvenlik Politikası

[Türkçe](#türkçe) · [English](#english)

## Türkçe

### Desteklenen sürümler

Güvenlik düzeltmeleri en son GitHub Release sürümü ve `main` dalındaki yaklaşan
sürüm için değerlendirilir. Eski Release paketleri aktif olarak desteklenmez.

### Bir güvenlik açığını bildirme

Lütfen hassas güvenlik açıklarını herkese açık Issue veya Discussion olarak
yazmayın. Depodaki **Security → Report a vulnerability** bağlantısını kullanarak
özel bir GitHub Security Advisory taslağı açın. Bu seçenek görünmüyorsa depo
sahibine yalnızca özel iletişim kanalı istemek için ulaşın; rapora token, parola,
Anahtar Zinciri içeriği veya gerçek kimlik bilgisi eklemeyin.

Raporda mümkünse şunlar bulunmalıdır:

- Etkilenen UsageBar sürümü ve macOS sürümü
- Sorunu yeniden üretmek için en küçük güvenli adımlar
- Beklenen ve gerçekleşen davranış
- Etkinin açıklaması
- Gerçek kimlik bilgileri yerine zararsız örnek veri

Rapor alındığında kapsam doğrulanacak, önem derecesi değerlendirilecek ve düzeltme
hazır olduğunda koordineli yayın zamanı görüşülecektir. Proje gönüllü olarak
yürütüldüğü için kesin yanıt süresi taahhüt edilmez.

### Güvenlik ve gizlilik sınırları

UsageBar mevcut yerel Codex ve Claude Code oturumlarını kullanır. API anahtarı,
parola, erişim belirteci, ham CLI çıktısı veya sağlayıcı yanıtı saklamaz. Yerel
geçmiş yalnızca zaman damgası ile kalan tam sayı yüzdesini, en fazla 24 saat
boyunca saklar.

Release paketleri şu anda ad-hoc imzalıdır ve Apple tarafından notarize
edilmemiştir. Developer ID ve notarization tamamlanana kadar Release sayfasındaki
SHA-256 değeri ile GitHub artifact attestation kaydı birlikte doğrulanmalıdır.

## English

### Supported versions

Security fixes are evaluated for the latest GitHub Release and the upcoming
version on `main`. Older Release packages are not actively supported.

### Reporting a vulnerability

Do not disclose sensitive vulnerabilities in a public Issue or Discussion. Use
the repository's **Security → Report a vulnerability** link to open a private
GitHub Security Advisory draft. If that option is unavailable, contact the
repository owner only to request a private channel; do not include tokens,
passwords, Keychain contents, or real credentials in the message.

Include the following when possible:

- Affected UsageBar and macOS versions
- Minimal, safe reproduction steps
- Expected and actual behavior
- A description of the impact
- Harmless sample data instead of real credentials

After receipt, the report will be scoped and assessed, and a coordinated
disclosure date can be discussed when a fix is ready. This is a volunteer
project, so no fixed response-time guarantee is offered.

### Security and privacy boundaries

UsageBar uses existing local Codex and Claude Code sessions. It does not store
API keys, passwords, access tokens, raw CLI output, or provider responses. Local
history stores only a timestamp and integer remaining percentage for at most 24
hours.

Release packages are currently ad-hoc signed and are not notarized by Apple.
Until Developer ID signing and notarization are available, verify both the
SHA-256 value on the Release page and the GitHub artifact attestation record.
