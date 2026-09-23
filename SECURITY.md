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

#### Mobil Eşitleme

Mobil Eşitleme, kullanım anlık görüntünü kendi iPhone'una sunar. **İsteğe
bağlıdır ve varsayılan olarak kapalıdır**; kapalıyken UsageBar hiçbir dinleyici
açmaz, hiçbir Tailscale komutu çalıştırmaz ve hiçbir mobil kimlik bilgisi
saklamaz.

- **Bulut arka ucu yoktur.** Yolda hiçbir UsageBar sunucusu bulunmaz; telefon
  Mac'ine doğrudan kendi Tailscale ağın üzerinden ulaşır.
- **Dinleyici yalnızca `127.0.0.1` adresine bağlanır**; LAN ya da tailnet
  adresine asla. Tek giriş noktası Tailscale Serve'dür ve Serve'ün eklediği
  kimlik başlığını anlamlı kılan da budur.
- **Tailscale Funnel asla kullanılmaz** ve UsageBar Tailscale'i yapılandırmaz.
  Yalnızca sabit mutlak yol üzerinden, shell kullanmadan `tailscale status
  --json` okuyabilir; Serve, Funnel, grant, ACL, tag, auth key veya OAuth
  istemcisi oluşturamaz ya da değiştiremez. `tailscale serve` komutu bilinçli
  bir kullanıcı eylemi olarak kalır.
- **Eşleştirme, QR içindeki tek kullanımlık bir koddur**; dakikalarla sınırlıdır
  ve bir kez kullanılır. Fotoğrafı sonrasında işe yaramaz ve içinde uzun ömürlü
  kimlik bilgisi, adres ya da kimlik taşımaz.
- **Mac özet saklar, sır değil.** Hem bearer hem Tailscale kimliği özet olarak
  tutulur, sabit zamanlı karşılaştırılır ve her ret aynı genel `401`'dir.
  Telefon bearer'ı iOS Keychain'de tutar.
- **Sağlayıcı kimlik bilgileri telefona geçmez.** Anlık görüntü yalnızca
  arındırılmış, şemada onaylı kullanım verisi taşır; token, çerez, ortam
  değişkeni, dosya yolu, ham sağlayıcı çıktısı ya da hata metni taşımaz.
- **Windows telefonu sunamaz.** Host tarafı yalnızca macOS'tur.

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

#### Mobile Sync

Mobile Sync serves your usage snapshot to your own iPhone. It is **optional and
disabled by default**; while it is off, UsageBar opens no listener, runs no
Tailscale command and stores no mobile credential.

- **No cloud backend.** There is no UsageBar server anywhere in the path. The
  phone reaches your Mac directly over your own Tailscale network.
- **The listener binds `127.0.0.1` and nothing else**, never a LAN or tailnet
  address. Tailscale Serve is the only ingress, and that is what makes the
  identity header Serve injects meaningful — a service on a routable interface
  could be called directly by anyone who supplies their own header value.
- **Tailscale Funnel is never used**, and UsageBar never configures Tailscale.
  It may read `tailscale status --json` through a fixed absolute path with no
  shell; it cannot create or change Serve, Funnel, grants, ACLs, tags, auth keys
  or OAuth clients. Running `tailscale serve` stays a deliberate user action.
- **Pairing is a one-time code in a QR**, valid for minutes and usable once. A
  photograph of it is worth nothing afterwards, and it carries no long-lived
  credential, address or identity.
- **The Mac stores digests, never secrets.** Both the bearer and the Tailscale
  identity are kept as digests and compared in constant time, and every refusal
  is the same generic `401`. The phone keeps its bearer in the iOS Keychain.
- **No provider credentials cross to the phone.** The snapshot carries only
  sanitized, schema-approved usage data — no tokens, cookies, environment
  variables, filesystem paths, raw provider output or provider error strings.
- **Windows cannot host the phone.** The host side is macOS only.
