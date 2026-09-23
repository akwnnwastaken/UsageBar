# Troubleshooting / Sorun giderme

[English](#english) · [Türkçe](#türkçe)

Nothing here asks you to turn off a security feature. If a step ever seems to,
it is not from this document.

---

<a id="english"></a>

## English

## Building and installing

### Xcode does not list my iPhone

Connect by cable and unlock the phone. If a **Trust This Computer** prompt
appears, tap Trust and enter the passcode; the prompt only appears while the
phone is unlocked. Then check Xcode ▸ Window ▸ Devices and Simulators.

A phone that was trusted once and is not trusted now usually just needs to be
unplugged, unlocked and plugged back in.

### "Developer Mode required"

iOS 16 and later refuse to run development-signed apps until Developer Mode is
on. Settings ▸ Privacy & Security ▸ **Developer Mode** ▸ on, then restart the
iPhone and confirm after it boots.

The Developer Mode row only appears after a development build has been installed
at least once, so install first, then look for it.

### "No profiles for 'com.…' were found" / "Failed to register bundle identifier"

Two different causes, same fix:

- You are still using `com.usagebar.mobilelab`, which belongs to someone else's
  Apple account. Choose your own namespace — see
  [Choosing a bundle namespace](SELF_BUILD.md#choosing-a-bundle-namespace).
- You have no local signing file. Run `./scripts/configure_ios_self_build.sh`.

Then in Xcode, select the target ▸ Signing & Capabilities and confirm your team
is selected with "Automatically manage signing" on.

### "Bundle identifier is not available"

Someone has already registered it — possibly you, on another Apple ID. Pick a
different namespace and rerun the configure script. Identifiers are global
across all Apple accounts.

### The app was installed but will not open: "Untrusted Developer"

Settings ▸ General ▸ **VPN & Device Management** ▸ your Apple ID ▸ **Trust**.
This is required once per development certificate.

### The app stopped launching after about a week

That is the free Personal Team provisioning expiring, not a defect. Plug the
phone in, open the project, press ⌘R. See
[The 7-day limit](SELF_BUILD.md#the-7-day-limit).

Widgets and controls stop with it, because they are part of the same install.

### Gatekeeper warns on first launch

UsageBar is ad-hoc signed and **not notarized**, so macOS refuses the first
launch of a downloaded copy.

Open it once from **System Settings ▸ Privacy & Security**, where a message
about the blocked app appears with an **Open Anyway** button, then confirm.

Do this only for an artifact you deliberately downloaded and whose SHA-256 you
verified:

```sh
shasum -a 256 <the UsageBar release ZIP you downloaded>
```

Do not disable Gatekeeper, and do not run `xattr` commands copied from the
internet to "fix" a warning — they remove the check for everything, not just
this app. Building UsageBar yourself from source avoids the warning entirely,
because a locally built app was never quarantined.

## Widgets and controls

### The widgets do not appear in the gallery

The widget extension installs with the app, so first confirm the app itself
launches. Then long-press the Home Screen ▸ **+** ▸ search for **UsageBar**.

If the app launches and the widgets are still missing, the extension did not
install — rebuild from Xcode and watch for a signing error on the
`UsageBarWidgets` target specifically.

### The Control Center controls are missing

Settings ▸ **Control Center** ▸ **Add a control**, then search for UsageBar.
There are three: Overview, Codex and Claude. They require iOS 18.

### A control shows only an icon

That is the system's layout, not a bug. At its smallest size iOS renders the
glyph alone; make the control wider in the Control Center editor to see the
text.

### A widget's countdown looks a few minutes stale

Expected. iOS decides when a widget re-evaluates, and UsageBar deliberately does
not add a timer, a background task or a shorter refresh interval to force it.
Open the app for an exact reading.

## Connecting

### The iPhone shows Tailscale as offline

Open the Tailscale app on the phone and reconnect; iOS drops the VPN profile
when the phone is idle on some configurations. Confirm both devices are on the
**same tailnet** — two personal accounts are two separate networks.

### "No serve config" / the phone cannot reach the Mac

Serve has not been configured, or was reset. On the Mac:

```sh
tailscale serve status
tailscale serve --bg 18642
```

See [TAILSCALE_SETUP.md](TAILSCALE_SETUP.md). UsageBar never configures Serve
for you.

### HTTPS certificates are not enabled

Without them your Mac has no `.ts.net` HTTPS name, and the app accepts nothing
else. Admin console ▸ DNS ▸ **HTTPS Certificates** ▸ Enable. Rename the Mac to
something generic *first* — see
[step 2](TAILSCALE_SETUP.md#2-name-the-mac-before-you-enable-certificates--this-one-matters).

### The QR will not scan

Raise the Mac's screen brightness and hold the phone 15–30 cm away. Grant the
camera permission when iOS asks — if you refused it earlier, re-enable it in
Settings ▸ UsageBar Mobile ▸ Camera.

The scanner ignores any QR that is not a UsageBar pairing code, rather than
guessing, so scanning something else does nothing at all.

### "Pairing expired" or the code stopped working

A pairing code is deliberately short-lived, single-use, and cancelled by a new
one. Choose **Pair iPhone…** on the Mac again and scan the fresh code.

### The phone shows old values and says "last known"

The Mac is asleep, offline or the host is not running. This is the accepted
tradeoff of talking directly to your own machine instead of a cloud service:
when the Mac is unreachable, the phone keeps the last reading it validated and
labels it as old rather than blanking the screen.

Wake the Mac, confirm UsageBar is running with Mobile Sync enabled,
and pull to refresh.

### The phone suddenly returned to the setup screen

Someone chose **Revoke Paired iPhone** on the Mac, or re-paired a different
phone. Revocation is immediate and clears the phone's cached data and its
widgets too. Pair again from the Mac.

### The widgets went blank but the app still works

The same revocation path, seen from the extension: with no credentials the
widgets and controls refuse to display a cached reading and clear their own
cache. That is how revoking from the Mac reaches a widget the app cannot touch.

### Values did not update while the phone was locked

While the device is locked the app cannot read its stored credential, so it does
not attempt a request that would be rejected. It keeps showing the last
validated reading and refreshes when you unlock. A locked phone is never treated
as a revoked one.

---

<a id="türkçe"></a>

## Türkçe

Buradaki hiçbir adım bir güvenlik özelliğini kapatmanı istemez. Bir adım öyle
görünüyorsa, bu belgeden gelmiyordur.

## Derleme ve kurulum

### Xcode iPhone'umu görmüyor

Kabloyla bağla ve telefonun kilidini aç. **Bu Bilgisayara Güven** sorusu
çıkarsa Güven'e dokunup parolayı gir; bu soru yalnızca telefon kilitsizken
çıkar. Sonra Xcode ▸ Window ▸ Devices and Simulators'a bak.

Daha önce güvenilmiş ama şu an güvenilmeyen bir telefon için genellikle çıkarıp,
kilidini açıp yeniden takmak yeterlidir.

### "Developer Mode required"

iOS 16 ve sonrası, Geliştirici Modu açılana kadar geliştirme imzalı uygulamaları
çalıştırmaz. Ayarlar ▸ Gizlilik ve Güvenlik ▸ **Geliştirici Modu** ▸ aç, sonra
iPhone'u yeniden başlat ve açılışta onayla.

Geliştirici Modu satırı ancak en az bir geliştirme derlemesi kurulduktan sonra
görünür; önce kur, sonra ara.

### "No profiles for 'com.…' were found" / "Failed to register bundle identifier"

İki ayrı neden, aynı çözüm:

- Hâlâ başka birinin Apple hesabına ait olan `com.usagebar.mobilelab`
  kullanıyorsun. Kendi ad alanını seç — bkz.
  [Bundle ad alanı seçmek](SELF_BUILD.md#bundle-ad-alanı-seçmek).
- Yerel imzalama dosyan yok. `./scripts/configure_ios_self_build.sh` çalıştır.

Sonra Xcode'da hedefi seç ▸ Signing & Capabilities: takımının seçili ve
"Automatically manage signing"in açık olduğunu doğrula.

### "Bundle identifier is not available"

Biri onu zaten kaydetmiş — belki de sen, başka bir Apple Kimliğiyle. Farklı bir
ad alanı seç ve yapılandırma betiğini yeniden çalıştır. Tanımlayıcılar tüm Apple
hesapları genelinde benzersizdir.

### Uygulama kuruldu ama açılmıyor: "Untrusted Developer"

Ayarlar ▸ Genel ▸ **VPN ve Aygıt Yönetimi** ▸ Apple Kimliğin ▸ **Güven**. Her
geliştirme sertifikası için bir kez gerekir.

### Uygulama bir hafta sonra açılmaz oldu

Bu, ücretsiz Personal Team sağlamasının süresinin dolmasıdır; bir kusur değil.
Telefonu tak, projeyi aç, ⌘R. Bkz.
[7 günlük sınır](SELF_BUILD.md#7-günlük-sınır).

Widget'lar ve kontroller de durur, çünkü aynı kurulumun parçasıdırlar.

### İlk açılışta Gatekeeper uyarısı

UsageBar ad-hoc imzalıdır ve **notarize edilmemiştir**; bu yüzden macOS
indirilen bir kopyanın ilk açılışını reddeder.

Bir kez **Sistem Ayarları ▸ Gizlilik ve Güvenlik** üzerinden aç: engellenen
uygulamayla ilgili mesajın yanında **Yine de Aç** düğmesi görünür, onayla.

Bunu yalnızca bilerek indirdiğin ve SHA-256'sını doğruladığın bir dosya için yap:

```sh
shasum -a 256 <indirdiğin UsageBar release ZIP dosyası>
```

Gatekeeper'ı kapatma ve bir uyarıyı "düzeltmek" için internetten kopyalanan
`xattr` komutlarını çalıştırma — bunlar denetimi yalnızca bu uygulama için değil,
her şey için kaldırır. Host'u kaynaktan kendin derlersen uyarı hiç çıkmaz, çünkü
yerel derlenen bir uygulama hiçbir zaman karantinaya alınmaz.

## Widget'lar ve kontroller

### Widget'lar galeride görünmüyor

Widget uzantısı uygulamayla birlikte kurulur; önce uygulamanın açıldığını
doğrula. Sonra Ana Ekran'a uzun bas ▸ **+** ▸ **UsageBar** ara.

Uygulama açılıyor ama widget'lar hâlâ yoksa uzantı kurulmamıştır — Xcode'dan
yeniden derle ve özellikle `UsageBarWidgets` hedefinde imzalama hatası olup
olmadığına bak.

### Denetim Merkezi kontrolleri yok

Ayarlar ▸ **Denetim Merkezi** ▸ **Denetim ekle**, sonra UsageBar'ı ara. Üç tane
vardır: Overview, Codex ve Claude. iOS 18 gerektirirler.

### Kontrolde yalnızca simge görünüyor

Bu sistemin yerleşimi, bir hata değil. En küçük boyutta iOS yalnızca simgeyi
çizer; metni görmek için kontrolü Denetim Merkezi düzenleyicisinde genişlet.

### Widget'taki geri sayım birkaç dakika geride

Beklenen davranış. Bir widget'ın ne zaman yeniden değerlendirileceğine iOS karar
verir ve UsageBar bunu zorlamak için bilerek zamanlayıcı, arka plan görevi ya da
daha kısa yenileme aralığı eklemez. Kesin değer için uygulamayı aç.

## Bağlantı

### iPhone'da Tailscale çevrimdışı görünüyor

Telefondaki Tailscale uygulamasını açıp yeniden bağlan; bazı yapılandırmalarda
telefon boştayken iOS VPN profilini düşürür. İki cihazın da **aynı tailnet**'te
olduğunu doğrula — iki kişisel hesap iki ayrı ağdır.

### "No serve config" / telefon Mac'e ulaşamıyor

Serve yapılandırılmamış ya da sıfırlanmış. Mac'te:

```sh
tailscale serve status
tailscale serve --bg 18642
```

Bkz. [TAILSCALE_SETUP.md](TAILSCALE_SETUP.md). UsageBar senin yerine Serve'ü
asla yapılandırmaz.

### HTTPS sertifikaları açık değil

Onlar olmadan Mac'inin `.ts.net` HTTPS adı olmaz ve uygulama başka hiçbir şeyi
kabul etmez. Yönetim konsolu ▸ DNS ▸ **HTTPS Certificates** ▸ Enable. **Önce**
Mac'e genel bir ad ver — bkz.
[2. adım](TAILSCALE_SETUP.md#2-sertifikayı-açmadan-önce-mace-ad-ver--bu-madde-önemli).

### QR taranmıyor

Mac'in ekran parlaklığını artır ve telefonu 15–30 cm uzakta tut. iOS sorduğunda
kamera iznini ver — daha önce reddettiysen Ayarlar ▸ UsageBar Mobile ▸ Kamera
üzerinden yeniden aç.

Tarayıcı, UsageBar eşleştirme kodu olmayan bir QR'ı tahmin etmeye çalışmadan yok
sayar; yani başka bir şey taramak hiçbir şey yapmaz.

### "Pairing expired" ya da kod çalışmaz oldu

Eşleştirme kodu bilerek kısa ömürlüdür, tek kullanımlıktır ve yenisi eskisini
iptal eder. Mac'te yeniden **iPhone Eşleştir…**'i seçip yeni kodu tarat.

### Telefon eski değerleri ve "last known" yazısını gösteriyor

Mac uykuda, çevrimdışı ya da host çalışmıyor. Bu, bir bulut servisi yerine
doğrudan kendi makinene bağlanmanın kabul edilmiş dengesidir: Mac'e
ulaşılamadığında telefon, doğruladığı son okumayı saklar ve ekranı boşaltmak
yerine onu "eski" olarak etiketler.

Mac'i uyandır, UsageBar'ın çalıştığını ve Mobil Eşitleme'nin açık
olduğunu doğrula, sonra aşağı çekerek yenile.

### Telefon birden kurulum ekranına döndü

Mac'te **Eşleşmiş iPhone'u Kaldır** seçilmiş ya da başka bir telefon
eşleştirilmiş. İptal anında etkilidir; telefonun önbelleğini ve widget'larını da
temizler. Mac'ten yeniden eşleştir.

### Widget'lar boşaldı ama uygulama çalışıyor

Aynı iptal yolunun uzantıdan görünümü: kimlik bilgisi yokken widget'lar ve
kontroller önbellekteki bir okumayı göstermeyi reddeder ve kendi önbelleklerini
temizler. Mac'ten yapılan iptal, uygulamanın erişemediği bir widget'a böyle
ulaşır.

### Telefon kilitliyken değerler güncellenmedi

Cihaz kilitliyken uygulama saklı kimlik bilgisini okuyamaz; bu yüzden
reddedilecek bir istek denemez. Doğruladığı son okumayı göstermeye devam eder ve
kilidi açtığında yeniler. Kilitli bir telefon asla iptal edilmiş sayılmaz.
