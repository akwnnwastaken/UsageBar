# Building UsageBar Mobile yourself / UsageBar Mobile'ı kendin derle

[English](#english) · [Türkçe](#türkçe)

UsageBar Mobile's iPhone app is distributed as **source**. There is no App Store
listing and no downloadable `.ipa`, because an iOS app can only be installed on
your iPhone if it is signed for *your* Apple account. You build it once in
Xcode, and it runs on your phone.

The Mac side is **UsageBar itself**. Mobile Sync is a feature of the desktop
app, off by default; there is no second Mac application to install.

---

<a id="english"></a>

## English

### What you will end up with

| Piece | Where it runs | How you get it |
| --- | --- | --- |
| UsageBar (with Mobile Sync) | your Mac | the desktop app you already run |
| UsageBar Mobile | your iPhone | build and install it yourself, in Xcode |
| Home / Lock Screen widgets | your iPhone | included in that build |
| Control Center controls | your iPhone | included in that build |

The phone talks only to your own Mac, over your own Tailscale network. There is
no UsageBar server anywhere in the path.

### Prerequisites

**Mac**

- macOS 13 or later.
- **Apple Silicon.** UsageBar for macOS is built and released for `arm64` only.
- **Xcode 16 or later**, from the Mac App Store or developer.apple.com. Xcode is
  a large download; start it early.
- Git, if you want to clone rather than download a source archive.
- [Tailscale](https://tailscale.com/download) for macOS.
- Codex CLI and/or Claude Code, if you want that provider's usage on your phone.
  UsageBar reads the sessions those tools already have; it never asks you for a
  key. You can run with only one of them.

**iPhone**

- **iOS 18 or later.** The app, the widgets and the controls all require it.
- Tailscale for iOS, signed into the same tailnet as the Mac.
- A cable, to install from Xcode the first time.
- **Developer Mode**, which iOS asks you to enable the first time a
  development-signed app is installed. Settings ▸ Privacy & Security ▸ Developer
  Mode, then restart the phone.

**Apple account**

- An Apple ID signed into Xcode: Xcode ▸ Settings ▸ Accounts ▸ **+**.
- A **free Personal Team is enough.** A paid Apple Developer Program membership
  is *not* required for this source-build path. The whole iPhone companion — the app,
  the widget extension and the Control Center controls — was developed and
  physically tested on a free Personal Team.
- A free Personal Team cannot create App Groups. It does not need to: see
  [Privacy and security](PRIVACY_AND_SECURITY.md).

> **A free Personal Team's provisioning expires.** See
> [The 7-day limit](#the-7-day-limit) before you decide this is for you.

### 1. Get the source

The iPhone companion lives in the main UsageBar repository. Take it from the
**`v2.3.0`** tag rather than `main`, so you build the same source the release
was cut from:

```sh
git clone --branch v2.3.0 https://github.com/akwnnwastaken/UsageBar.git
cd UsageBar
```

Or download the **Source code (zip)** attached to the
[`v2.3.0` release](https://github.com/akwnnwastaken/UsageBar/releases/tag/v2.3.0)
and unzip it.

The Xcode project is at `ios/UsageBarMobileLab/`.

### 2. Configure signing

Two things differ per person: your Apple **Team ID**, and the **bundle
namespace** the app is registered under. Neither is in the source, and neither
should ever be committed.

`com.usagebar.mobilelab` is already registered to the maintainer's Apple
account, and no two Apple accounts can claim the same identifier, so **you must
choose your own namespace.** See [Choosing a bundle namespace](#choosing-a-bundle-namespace).

Run the helper from the root of the source tree:

```sh
./scripts/configure_ios_self_build.sh
```

It asks for your Team ID and your namespace, validates both, and writes one
untracked file:

```
ios/UsageBarMobileLab/Config/LocalSigning.xcconfig
```

It contacts nothing, creates no certificates and touches no tracked file. Xcode
creates the signing assets itself on the first device build.

To do it by hand instead:

```sh
cd ios/UsageBarMobileLab
cp Config/LocalSigning.example.xcconfig Config/LocalSigning.xcconfig
```

then edit the two values in the copy. Your Team ID is in Xcode ▸ Settings ▸
Accounts ▸ (your Apple ID) ▸ Manage Certificates, and on your membership page at
developer.apple.com. It is ten uppercase letters and digits.

**Never commit `LocalSigning.xcconfig`,** and do not paste it into an issue or a
pull request.

### Choosing a bundle namespace

Pick something you control, in reverse-DNS form:

```
com.yourname.usagebarmobile
```

You do not need to own the domain. You do need it to be unique to your Apple
account. Do not use `com.example.…` on a real device — it is a documentation
placeholder, and the helper script rejects it.

Everything else derives from that one value:

| Target | Identifier |
| --- | --- |
| App | `com.yourname.usagebarmobile` |
| Widget & control extension | `com.yourname.usagebarmobile.widgets` |
| Unit tests | `com.yourname.usagebarmobile.tests` |
| Shared Keychain group | `<your team prefix>.com.yourname.usagebarmobile.shared` |

They move together on purpose. The widget extension's identifier has to be a
child of the app's, and the Keychain group has to be identical on both, or the
widget cannot read the connection the app paired with.

### 3. Build and install on the iPhone

1. Open `ios/UsageBarMobileLab/UsageBarMobileLab.xcodeproj`.
2. Connect the iPhone by cable and unlock it. Tap **Trust This Computer** if
   asked.
3. Choose your iPhone as the run destination, next to the scheme name.
4. Select the **UsageBarMobileLab** target ▸ **Signing & Capabilities**, and
   confirm your team is selected and "Automatically manage signing" is on. The
   identifiers should already read your own namespace.
5. Press **Run** (⌘R). The first build registers the App IDs with Apple and
   creates a development profile.
6. On the iPhone, the first launch of a development app is refused until you
   trust the certificate: Settings ▸ General ▸ VPN & Device Management ▸ your
   Apple ID ▸ **Trust**.

The widget extension and the Control Center controls install with the app; there
is nothing separate to build.

### 4. The Mac side

Nothing to install. Mobile Sync lives in UsageBar itself and is **off until you
turn it on**: until then UsageBar opens no listener, runs no Tailscale command
and holds no mobile credential.

> **Moving from the standalone UsageBar Mobile Host 0.1.0?** Pair once more.
> UsageBar keeps its own preference and its own Keychain entry, and nothing is
> migrated from the separate host — deliberately, so a device paired with one
> is not silently paired with the other. The iPhone app itself does not need
> rebuilding or reinstalling for this.

### 5. Connect Tailscale, then pair

Follow [docs/TAILSCALE_SETUP.md](TAILSCALE_SETUP.md). In short: same tailnet on
both devices, HTTPS Certificates enabled for the tailnet, and one `tailscale
serve` command on the Mac.

Then, on the Mac: open UsageBar, connect Codex and/or Claude, expand the lower
menu controls, and under **Mobile Sync** choose **Enable Mobile Sync** and then
**Pair iPhone…**. On the phone: open UsageBar Mobile, tap **Scan Mac Pairing
QR**, allow the camera, and scan.

The dashboard fills in immediately. Add widgets by long-pressing the Home
Screen, and controls from Settings ▸ Control Center ▸ Add a control.

### The 7-day limit

With a **free Personal Team**, Apple issues development provisioning that
expires after about **7 days**. When it does, the app stops launching on the
phone until you rebuild and reinstall it from Xcode — plug in, press ⌘R, done.

This affects the widgets and the Control Center controls too: they are part of
the same development install.

Two things worth being clear about:

- **This is an Apple limitation on free accounts, not a timer in UsageBar.**
  Nothing in this project expires anything.
- **A paid Apple Developer Program membership lifts it** to a one-year profile.
  It is not required, and nothing else depends on it.

Your pairing survives a reinstall as long as the bundle identifier does not
change, so you normally do not re-pair. If the app comes back to the setup
screen, pair again — it takes a few seconds.

Apple changes these terms from time to time. If your experience differs from the
above, Apple's current documentation is authoritative.

### Running the tests

From the source root:

```sh
swift test
```

builds and tests the shared Swift package — the snapshot schema, the sync
boundary, the pairing protocol and the Mac host logic.

The iOS suite runs on the simulator and needs no signing configuration at all:

```sh
cd ios/UsageBarMobileLab
xcodebuild test -project UsageBarMobileLab.xcodeproj \
  -scheme UsageBarMobileLab \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Use any installed simulator name. If you have no local signing file, both of
these still work; only installing on a physical device needs a team.

### What is not in this release

- **No Windows host.** The Windows build of UsageBar cannot serve a phone in
  2.3.0. macOS is the only host.
- **No iPad or Apple Watch app.**
- **No App Store build and no `.ipa` download**, by design.
- **No automatic Tailscale Serve configuration.** You run one command yourself.

---

<a id="türkçe"></a>

## Türkçe

### Sonuçta elinde ne olacak

| Parça | Nerede çalışır | Nasıl edinilir |
| --- | --- | --- |
| UsageBar (Mobil Eşitleme ile) | Mac'inde | zaten kullandığın masaüstü uygulaması |
| UsageBar Mobile | iPhone'unda | Xcode ile kendin derleyip kurarsın |
| Ana Ekran / Kilit Ekranı widget'ları | iPhone'unda | aynı derlemenin içinde |
| Denetim Merkezi kontrolleri | iPhone'unda | aynı derlemenin içinde |

Telefon yalnızca kendi Mac'inle, kendi Tailscale ağın üzerinden konuşur. Yolun
hiçbir yerinde bir UsageBar sunucusu yoktur.

### Gerekenler

**Mac**

- macOS 13 veya üstü.
- **Apple Silicon.** Mac host yalnızca `arm64` için derlenir ve yayınlanır.
- **Xcode 16 veya üstü** (Mac App Store ya da developer.apple.com). Xcode büyük
  bir indirmedir; erken başlat.
- Kaynak arşivini açmak yerine klonlamak istersen Git.
- macOS için [Tailscale](https://tailscale.com/download).
- Telefonunda o sağlayıcının kullanımını görmek istiyorsan Codex CLI ve/veya
  Claude Code. UsageBar bu araçların zaten açık olan oturumlarını okur; senden
  asla anahtar istemez. Yalnızca biriyle de çalışır.

**iPhone**

- **iOS 18 veya üstü.** Uygulama, widget'lar ve kontroller bunu gerektirir.
- iOS için Tailscale, Mac ile **aynı** tailnet'te oturum açmış olarak.
- İlk kurulumda Xcode'dan yüklemek için bir kablo.
- **Geliştirici Modu**: geliştirme imzalı bir uygulama ilk kez kurulduğunda iOS
  bunu ister. Ayarlar ▸ Gizlilik ve Güvenlik ▸ Geliştirici Modu, sonra telefonu
  yeniden başlat.

**Apple hesabı**

- Xcode'da oturum açmış bir Apple Kimliği: Xcode ▸ Settings ▸ Accounts ▸ **+**.
- **Ücretsiz Personal Team yeterlidir.** Bu kaynaktan-derleme yolu için ücretli
  Apple Developer Program üyeliği **gerekmez**. iPhone eşlikçisinin tamamı —
  uygulama, widget uzantısı ve Denetim Merkezi kontrolleri — ücretsiz bir
  Personal Team üzerinde geliştirildi ve fiziksel cihazda test edildi.
- Ücretsiz Personal Team App Group oluşturamaz. Zaten gerekmiyor:
  [Gizlilik ve güvenlik](PRIVACY_AND_SECURITY.md).

> **Ücretsiz Personal Team'in sağlaması süresi dolar.** Karar vermeden önce
> [7 günlük sınır](#7-günlük-sınır) bölümünü oku.

### 1. Kaynağı al

iPhone eşlikçisi ana UsageBar deposunun içindedir. `main` yerine **`v2.3.0`**
etiketinden al; böylece sürümün kesildiği kaynağı derlemiş olursun:

```sh
git clone --branch v2.3.0 https://github.com/akwnnwastaken/UsageBar.git
cd UsageBar
```

Ya da [`v2.3.0` sürümüne](https://github.com/akwnnwastaken/UsageBar/releases/tag/v2.3.0)
eklenen **Source code (zip)** dosyasını indirip aç.

Xcode projesi `ios/UsageBarMobileLab/` altındadır.

### 2. İmzalamayı yapılandır

Kişiden kişiye değişen iki şey var: Apple **Team ID**'n ve uygulamanın
kaydedildiği **bundle ad alanı**. İkisi de kaynak kodda değildir ve ikisi de
asla commit edilmemelidir.

`com.usagebar.mobilelab` zaten geliştiricinin Apple hesabına kayıtlıdır ve iki
Apple hesabı aynı tanımlayıcıyı alamaz; bu yüzden **kendi ad alanını seçmelisin.**
Bkz. [Bundle ad alanı seçmek](#bundle-ad-alanı-seçmek).

Kaynak ağacının kökünde çalıştır:

```sh
./scripts/configure_ios_self_build.sh
```

Team ID'ni ve ad alanını sorar, ikisini de doğrular ve izlenmeyen tek bir dosya
yazar:

```
ios/UsageBarMobileLab/Config/LocalSigning.xcconfig
```

Hiçbir yere bağlanmaz, sertifika oluşturmaz, izlenen hiçbir dosyaya dokunmaz.
İmzalama varlıklarını ilk cihaz derlemesinde Xcode kendisi oluşturur.

Elle yapmak istersen:

```sh
cd ios/UsageBarMobileLab
cp Config/LocalSigning.example.xcconfig Config/LocalSigning.xcconfig
```

ve kopyadaki iki değeri düzenle. Team ID'n Xcode ▸ Settings ▸ Accounts ▸ (Apple
Kimliğin) ▸ Manage Certificates altında ve developer.apple.com üyelik sayfanda
yazar. On büyük harf ve rakamdan oluşur.

**`LocalSigning.xcconfig` dosyasını asla commit etme** ve içeriğini bir issue ya
da pull request'e yapıştırma.

### Bundle ad alanı seçmek

Sana ait, ters-DNS biçiminde bir şey seç:

```
com.adin.usagebarmobile
```

Alan adının sahibi olman gerekmez; Apple hesabın için benzersiz olması gerekir.
Gerçek bir cihazda `com.example.…` kullanma — o bir belge yer tutucusudur ve
yardımcı betik onu reddeder.

Geri kalan her şey bu tek değerden türer:

| Hedef | Tanımlayıcı |
| --- | --- |
| Uygulama | `com.adin.usagebarmobile` |
| Widget ve kontrol uzantısı | `com.adin.usagebarmobile.widgets` |
| Birim testleri | `com.adin.usagebarmobile.tests` |
| Paylaşılan Anahtar Zinciri grubu | `<team ön eki>.com.adin.usagebarmobile.shared` |

Bunlar bilerek birlikte hareket eder. Widget uzantısının tanımlayıcısı
uygulamanınkinin altında olmak zorundadır ve Anahtar Zinciri grubu ikisinde de
aynı olmalıdır; yoksa widget, uygulamanın eşleştirdiği bağlantıyı okuyamaz.

### 3. iPhone'a derle ve kur

1. `ios/UsageBarMobileLab/UsageBarMobileLab.xcodeproj` dosyasını aç.
2. iPhone'u kabloyla bağla ve kilidini aç. Sorarsa **Bu Bilgisayara Güven**'e
   dokun.
3. Şema adının yanından çalıştırma hedefi olarak iPhone'unu seç.
4. **UsageBarMobileLab** hedefi ▸ **Signing & Capabilities**: takımının seçili
   ve "Automatically manage signing"in açık olduğunu doğrula. Tanımlayıcılar
   kendi ad alanını göstermelidir.
5. **Run** (⌘R). İlk derleme App ID'leri Apple'a kaydeder ve bir geliştirme
   profili oluşturur.
6. iPhone'da geliştirme uygulamasının ilk açılışı sertifikaya güvenene kadar
   reddedilir: Ayarlar ▸ Genel ▸ VPN ve Aygıt Yönetimi ▸ Apple Kimliğin ▸
   **Güven**.

Widget uzantısı ve Denetim Merkezi kontrolleri uygulamayla birlikte kurulur;
ayrıca derlenecek bir şey yoktur.

### 4. Mac tarafı

Kurulacak bir şey yok. Mobil Eşitleme UsageBar'ın kendi içindedir ve **sen
açana kadar kapalıdır**: o ana dek UsageBar hiçbir dinleyici açmaz, hiçbir
Tailscale komutu çalıştırmaz ve hiçbir mobil kimlik bilgisi tutmaz.

> **Ayrı UsageBar Mobile Host 0.1.0'dan mı geçiyorsun?** Bir kez daha eşleştir.
> UsageBar kendi tercihini ve kendi Keychain kaydını kullanır; ayrı host'tan
> hiçbir şey taşınmaz — bilerek, çünkü biriyle eşleşmiş bir cihaz diğeriyle
> sessizce eşleşmiş sayılmamalı. iPhone uygulamasının bunun için yeniden
> derlenmesi ya da kurulması gerekmez.

### 5. Tailscale'i bağla, sonra eşleştir

[docs/TAILSCALE_SETUP.md](TAILSCALE_SETUP.md) adımlarını izle. Kısaca: iki
cihazda aynı tailnet, tailnet için HTTPS Sertifikaları açık ve Mac'te tek bir
`tailscale serve` komutu.

Sonra Mac'te: UsageBar'ı aç, Codex ve/veya Claude'u bağla, alt menü denetimlerini genişlet ve **Mobil
Eşitleme**'yi aç ve **iPhone Eşleştir…**'i seç. Telefonda: UsageBar Mobile'ı aç,
**Scan Mac Pairing QR**'a dokun, kameraya izin ver ve kodu taret.

Pano hemen dolar. Widget'ları Ana Ekran'a uzun basarak, kontrolleri Ayarlar ▸
Denetim Merkezi ▸ Denetim ekle üzerinden eklersin.

### 7 günlük sınır

**Ücretsiz Personal Team** ile Apple'ın verdiği geliştirme sağlaması yaklaşık
**7 gün** sonra sona erer. Süresi dolduğunda uygulama, Xcode'dan yeniden
derleyip kurana kadar telefonda açılmaz — kabloyu tak, ⌘R, bitti.

Bu widget'ları ve Denetim Merkezi kontrollerini de etkiler: onlar da aynı
geliştirme kurulumunun parçasıdır.

Net olmakta fayda var:

- **Bu, ücretsiz hesaplardaki bir Apple sınırlamasıdır, UsageBar'daki bir
  zamanlayıcı değil.** Bu projede hiçbir şeyin süresi dolmaz.
- **Ücretli Apple Developer Program üyeliği bu sınırı kaldırır** ve profili bir
  yıla çıkarır. Gerekli değildir; başka hiçbir şey buna bağlı değildir.

Bundle tanımlayıcısı değişmediği sürece eşleştirmen yeniden kurulumdan sağ
çıkar, yani normalde yeniden eşleştirmen gerekmez. Uygulama kurulum ekranına
dönerse birkaç saniyede yeniden eşleştir.

Apple bu koşulları zaman zaman değiştirir. Deneyimin yukarıdakinden farklıysa
Apple'ın güncel belgeleri esastır.

### Testleri çalıştırmak

Kaynak kökünden:

```sh
swift test
```

paylaşılan Swift paketini derler ve test eder — anlık görüntü şeması, eşitleme
sınırı, eşleştirme protokolü ve Mac host mantığı.

iOS takımı simülatörde çalışır ve hiçbir imzalama yapılandırması gerektirmez:

```sh
cd ios/UsageBarMobileLab
xcodebuild test -project UsageBarMobileLab.xcodeproj \
  -scheme UsageBarMobileLab \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

Kurulu herhangi bir simülatör adını kullanabilirsin. Yerel imzalama dosyan yoksa
ikisi de yine çalışır; yalnızca fiziksel cihaza kurulum bir takım gerektirir.

### Bu sürümde olmayanlar

- **Windows host yok.** UsageBar'ın Windows sürümü 2.3.0'da bir telefona
  hizmet veremez. Tek host macOS'tur.
- **iPad veya Apple Watch uygulaması yok.**
- **App Store derlemesi ve `.ipa` indirmesi yok**; bu bilinçli bir tercih.
- **Otomatik Tailscale Serve yapılandırması yok.** Tek komutu sen çalıştırırsın.
