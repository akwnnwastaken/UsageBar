# Privacy and security / Gizlilik ve güvenlik

[English](#english) · [Türkçe](#türkçe)

This is the plain-language version. The engineering detail is in
[`mobile-sync-threat-model.md`](mobile-sync-threat-model.md) and
[`mobile-live-sync-pairing.md`](mobile-live-sync-pairing.md).

---

<a id="english"></a>

## English

### There is no UsageBar cloud

Your iPhone asks **your Mac** for your usage, directly. Nothing is uploaded, no
account is created, and there is no UsageBar server to hold your data or to be
breached.

Tailscale carries the connection between the two devices. It is the network, not
a backend: your usage never rests on Tailscale's infrastructure either. And
UsageBar Mobile is not itself a VPN — it contains no VPN profile and no
Tailscale SDK, and it speaks ordinary HTTPS to a name your own Tailscale client
resolves.

### What the phone receives

Only this, and it is built field by field rather than by serialising whatever
the Mac happens to be holding:

- remaining percentages
- which usage window each percentage belongs to, and which one is the headline
- when each window resets
- whether each provider is connected and collecting
- when each reading was actually measured

### What the phone never receives

- your provider password, API key or access token — there are none on the phone
  to receive, and none on the Mac to send
- raw Codex or Claude output, and provider error text
- your 24-hour local usage history, which stays on the Mac
- file paths, environment variables or anything about your machine
- your Tailscale hostname, tailnet name or `100.x` address — those are personal
  metadata, and the synced data format has no field that could carry one

There is no field for any of these. That is the point: they are not filtered
out, they were never representable.

### Pairing

You pair once, by scanning a QR code on the Mac with the phone.

The QR contains a **one-time code** that is valid for a couple of minutes, can
be used exactly once, and is cancelled by a new one, a restart or a cancel. It
carries no long-lived password, no identity and no account. A QR code on a
screen is photographable, so nothing worth having tomorrow is put in it.

During the exchange the Mac issues a long-lived credential and sends it to the
phone once.

### Where credentials live

| | |
| --- | --- |
| The phone | keeps the credential **and** the Mac's hostname in the iOS Keychain, device-only, never in a backup, never in a log |
| The Mac | keeps only a **digest** of that credential, and a digest of the Tailscale identity that paired — never the credential itself, never your Tailscale email |

The Mac cannot replay your credential because it does not have it. A digest
proves "this is the same caller" without being usable as a password.

### Being on the network is not permission

Every request has to carry two things: the credential, and the Tailscale
identity it was issued to. Both are checked, and both are compared in a way that
does not leak the answer through timing.

So a credential stolen and used from a different Tailscale account fails, and
another device that merely joins your tailnet still cannot read your usage. When
a request is refused, the answer is an identical generic rejection every time —
it never says *which* factor was wrong.

### Revoking

| Action | Effect |
| --- | --- |
| **Revoke Paired iPhone**, on the Mac | the phone's credential stops working immediately; the app *and* the widgets clear their data and return to not-configured |
| **Pair iPhone…** again | issues a new credential and invalidates the old one |
| **Forget Connection**, on the phone | removes the credential, the hostname and the cached data from the phone |

Revocation reaches the widgets too, even though the app cannot reach into their
storage: they check for the credential *before* displaying anything, so no
credential means nothing is shown, whatever they had cached.

### Offline, asleep and locked

- **Mac asleep or offline** — the phone keeps the last reading it validated and
  labels it as old. This is the accepted cost of talking to your own machine
  instead of a cloud service.
- **Phone locked** — the app cannot read its credential, so it makes no request
  at all and keeps showing the last reading. A locked phone is never mistaken
  for a revoked one.
- **A corrupt cache** is discarded, never repaired and never fatal.

### The parts of the Mac that stay locked down

- The service listens on `127.0.0.1` and nothing else. Tailscale Serve is the
  only way in, which is what makes the identity it injects meaningful.
- UsageBar never configures Tailscale — not Serve, not Funnel, not DNS, not
  grants, ACLs, tags or keys. It reads your status, read-only.
- **Tailscale Funnel is never used.** Funnel would publish the service to the
  public internet.
- Mobile Sync only runs inside UsageBar itself, and only once you enable it.
  A process that is not UsageBar — a test runner, an unbundled build —
  contains the same code and still never opens a listener.
- If sync fails for any reason, the menu bar, the menus and the history keep
  working. Sync is never allowed to break the desktop app.

### On the phone, by design

No background task scheduler, no push notifications, no silent push and no
polling loop. Widgets and controls refresh when iOS decides to ask them, which
is why a countdown can be a few minutes behind.

### Reporting a problem

See [SECURITY.md](../../SECURITY.md). Please do not include real credentials,
hostnames or Keychain contents in a report.

---

<a id="türkçe"></a>

## Türkçe

### UsageBar bulutu diye bir şey yok

iPhone'un kullanım verini doğrudan **kendi Mac'inden** ister. Hiçbir şey
yüklenmez, hesap açılmaz ve verini tutacak ya da sızdırabilecek bir UsageBar
sunucusu yoktur.

İki cihaz arasındaki bağlantıyı Tailscale taşır. O bir ağdır, arka uç değil:
kullanım verin Tailscale'in altyapısında da durmaz. Ayrıca UsageBar Mobile'ın
kendisi bir VPN değildir — içinde VPN profili ya da Tailscale SDK'sı yoktur;
kendi Tailscale istemcinin çözdüğü bir ada sıradan HTTPS konuşur.

### Telefona ne gider

Yalnızca şunlar — ve Mac'in elindeki nesne olduğu gibi serileştirilerek değil,
alan alan kurularak:

- kalan yüzdeler
- her yüzdenin hangi kullanım penceresine ait olduğu ve hangisinin başlık olduğu
- her pencerenin ne zaman sıfırlanacağı
- her sağlayıcının bağlı olup olmadığı ve veri toplayıp toplamadığı
- her okumanın gerçekte ne zaman ölçüldüğü

### Telefona asla gitmeyenler

- sağlayıcı parolan, API anahtarın veya erişim belirtecin — telefonda alınacak,
  Mac'te gönderilecek böyle bir şey yok
- ham Codex veya Claude çıktısı ve sağlayıcı hata metinleri
- Mac'te kalan 24 saatlik yerel kullanım geçmişin
- dosya yolları, ortam değişkenleri ya da makinenle ilgili herhangi bir bilgi
- Tailscale ana bilgisayar adın, tailnet adın veya `100.x` adresin — bunlar
  kişisel üstverilerdir ve eşitlenen veri biçiminde bunları taşıyabilecek bir
  alan yoktur

Bunların hiçbiri için bir alan yok. Mesele de bu: süzülüp atılmıyorlar, hiçbir
zaman ifade edilebilir olmadılar.

### Eşleştirme

Bir kez eşleştirirsin: Mac'teki QR kodunu telefonla taratarak.

QR, birkaç dakika geçerli olan, tam olarak bir kez kullanılabilen ve yenisi,
yeniden başlatma ya da iptal tarafından geçersiz kılınan **tek kullanımlık bir
kod** içerir. İçinde uzun ömürlü bir parola, bir kimlik ya da bir hesap yoktur.
Ekrandaki bir QR fotoğraflanabilir; bu yüzden içine yarın da işe yarayacak
hiçbir şey konmaz.

Değişim sırasında Mac uzun ömürlü bir kimlik bilgisi üretir ve telefona bir
kez gönderir.

### Kimlik bilgileri nerede durur

| | |
| --- | --- |
| Telefon | kimlik bilgisini **ve** Mac'in ana bilgisayar adını iOS Anahtar Zinciri'nde tutar; yalnızca bu cihazda, yedeklerde değil, kayıtlarda değil |
| Mac | yalnızca o kimlik bilgisinin bir **özetini** ve eşleşen Tailscale kimliğinin özetini tutar — kimlik bilgisinin kendisini değil, Tailscale e-postanı hiç değil |

Mac senin kimlik bilgini tekrar oynatamaz, çünkü onda yok. Özet, "bu aynı
arayan mı?" sorusunu parola olarak kullanılamadan yanıtlar.

### Ağda olmak izin değildir

Her istek iki şey taşımak zorundadır: kimlik bilgisi ve onun verildiği Tailscale
kimliği. İkisi de denetlenir ve ikisi de yanıtı zamanlamayla sızdırmayacak
biçimde karşılaştırılır.

Yani çalınıp başka bir Tailscale hesabından kullanılan bir kimlik bilgisi
başarısız olur; tailnet'ine katılan başka bir cihaz da kullanımını okuyamaz. Bir
istek reddedildiğinde yanıt her seferinde aynı genel rettir — **hangi** etkenin
yanlış olduğunu asla söylemez.

### İptal

| Eylem | Etkisi |
| --- | --- |
| Mac'te **Eşleşmiş iPhone'u Kaldır** | telefonun kimlik bilgisi anında çalışmaz olur; uygulama **ve** widget'lar verilerini temizleyip yapılandırılmamış duruma döner |
| Yeniden **iPhone Eşleştir…** | yeni bir kimlik bilgisi üretir ve eskisini geçersiz kılar |
| Telefonda **Forget Connection** | kimlik bilgisini, ana bilgisayar adını ve önbellekteki veriyi telefondan siler |

İptal, uygulama widget'ların deposuna erişemese bile onlara da ulaşır:
widget'lar bir şey göstermeden **önce** kimlik bilgisini denetler, yani kimlik
bilgisi yoksa önbelleklerinde ne olursa olsun hiçbir şey gösterilmez.

### Çevrimdışı, uykuda ve kilitli

- **Mac uykuda veya çevrimdışı** — telefon doğruladığı son okumayı saklar ve onu
  eski olarak etiketler. Bu, bir bulut servisi yerine kendi makinenle
  konuşmanın kabul edilmiş bedelidir.
- **Telefon kilitli** — uygulama kimlik bilgisini okuyamaz, bu yüzden hiç istek
  yapmaz ve son okumayı göstermeye devam eder. Kilitli bir telefon asla iptal
  edilmiş sanılmaz.
- **Bozuk bir önbellek** atılır; onarılmaz ve asla ölümcül değildir.

### Mac tarafında kapalı kalan şeyler

- Servis yalnızca `127.0.0.1`'i dinler, başka hiçbir arayüzü değil. Tek giriş
  yolu Tailscale Serve'dür; onun eklediği kimliği anlamlı kılan da budur.
- UsageBar Tailscale'i asla yapılandırmaz — ne Serve, ne Funnel, ne DNS, ne
  grant, ACL, tag veya anahtar. Durumunu salt-okunur okur.
- **Tailscale Funnel asla kullanılmaz.** Funnel servisi halka açık internete
  yayınlardı.
- Mobil Eşitleme yalnızca UsageBar'ın kendi içinde ve ancak sen açtıktan
  sonra çalışır. UsageBar olmayan bir süreç — test koşucusu, paketlenmemiş bir
  UsageBar derlemesi aynı kodu içerir ve yine de asla dinleyici açmaz.
- Eşitleme herhangi bir nedenle bozulursa menü çubuğu, menüler ve geçmiş
  çalışmaya devam eder. Eşitlemenin masaüstü uygulamasını bozmasına izin
  verilmez.

### Telefonda, tasarım gereği

Arka plan görev zamanlayıcısı yok, anında bildirim yok, sessiz push yok, yoklama
döngüsü yok. Widget'lar ve kontroller iOS sorduğunda yenilenir; bir geri sayımın
birkaç dakika geride kalabilmesinin nedeni budur.

### Sorun bildirme

Bkz. [SECURITY.md](../../SECURITY.md). Lütfen bildirimlere gerçek kimlik
bilgilerini, ana bilgisayar adlarını veya Anahtar Zinciri içeriğini ekleme.
