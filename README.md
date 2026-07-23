# UsageBar

[Türkçe](#türkçe) · [English](#english)

## Türkçe

Codex ve Claude Code kullanım limitlerini macOS menü çubuğunda gösteren küçük ve yerel bir uygulama.

UsageBar, seçtiğiniz sağlayıcının **kalan kullanım oranını** simgesiyle birlikte üst çubukta gösterir. Ayrıntı menüsünde kullanım pencerelerini, kalan yüzdeleri ve sıfırlanmaya kalan süreyi görebilirsiniz.

> [!NOTE]
> `main` dalı yaklaşan **v1.5.0** sürümünün kaynak kodunu içerir. Şu an indirilebilen son paket **v1.4.4** sürümüdür; v1.5.0 yayımlanana kadar aşağıdaki yeni özellikleri denemek için kaynak koddan derleme yapabilirsiniz.

### Özellikler

- Codex ve Claude Code kullanımını tek uygulamada izler.
- Menü çubuğunda seçili sağlayıcının aktif kullanım penceresine ait kalan oranı gösterir.
- 5 saatlik, haftalık ve sağlayıcının döndürdüğü diğer süreli pencereleri ayrı ayrı listeler; yalnızca hesapta bulunan pencereleri gösterir.
- Sıfırlama zamanını yüzde bilgisinin altında gösterir (`1sa 15dk` / `1h 15m`).
- Kalan oranı seviyesine göre yeşil, turuncu veya kırmızı renklendirir.
- Menü çubuğundaki yüzdeyi kritik seviyelerde turuncu veya kırmızı gösterir; renkler kapatılabilir ve üç farklı eşik profili seçilebilir.
- İstenirse menü çubuğunda seçili kullanım penceresinin sıfırlanma sayacını da gösterir.
- Üst çubukta gösterilecek sağlayıcıyı `Codex | Claude` anahtarıyla değiştirir.
- İki sağlayıcı bağlıyken `Otomatik` moduyla Codex ve Claude arasında 30 saniyede bir geçiş yapar.
- Her kullanım penceresinin 24 saate kadar kalan yüzde geçmişini ayrı bir yerel mini grafikte gösterir. Grafik gerçek kayıt aralığını, başlangıç/bitiş yüzdelerini ve değişimi yazar; küçük hareketleri uyarlanabilir ölçekle, sıfırlanmaları işaretlerle görünür kılar. Tek ölçümlük ±1 puan yuvarlama dalgalanmaları yalnızca çizimde yumuşatılır.
- Sağlayıcı geçici olarak yanıt vermezse son başarılı değeri zamanı ve hata nedeni ile eski veri olarak göstermeye devam eder; eski ölçüm geçmişe yeniden yazılmaz.
- Sürüm, macOS, bağlantı durumu, pencere türleri ve güvenli hata kodlarından oluşan bir tanılama özetini panoya kopyalar. Ham CLI çıktısı, dosya yolu veya kimlik bilgisi eklemez.
- macOS Giriş Öğeleri üzerinden Mac açılışında otomatik başlatılabilir.
- İlk açılışta macOS diline göre Türkçe veya İngilizce arayüz seçer; kullanıcı seçimini sonraki açılışlar için saklar.
- Her 5 dakikada bir ve menü yeniden açıldığında kullanım verisini yeniler.
- Dock simgesi veya ana pencere açmadan yalnızca menü çubuğunda çalışır.

### Yüzde nasıl hesaplanıyor?

Üst çubuktaki değer **kullanılan değil, kalan yüzdedir**.

- **Claude Code:** 5 saatlik pencere varsa menü çubuğunda her zaman onu gösterir. Bu veri yoksa haftalık pencereye geri döner.
- **Codex:** Hesabın sunduğu pencereler arasından en düşük kalan oranı gösterir. Hesap yalnızca haftalık pencere sunuyorsa onu kullanır.

Menüye tıkladığınızda sağlayıcının sunduğu tüm pencereleri ayrı ayrı görebilirsiniz.

### Gereksinimler

- macOS 13 veya daha yeni bir sürüm
- Codex için ChatGPT uygulaması veya giriş yapılmış Codex CLI
- Claude için giriş yapılmış Claude Code CLI
- Kaynak koddan derlemek için Xcode Command Line Tools

Yalnızca kullanmak istediğiniz sağlayıcının kurulu olması yeterlidir.

### İndir ve kur

1. [Releases](https://github.com/akwnnwastaken/UsageBar/releases) sayfasından en güncel `macOS-arm64.zip` dosyasını indirin.
2. ZIP dosyasını açın ve `UsageBar.app` uygulamasını **Applications** klasörüne taşıyın.
3. UsageBar'ı açın; menü çubuğundaki `%—` simgesinden sağlayıcınızı bağlayın.

> [!WARNING]
> Mevcut Beta paketi Apple Silicon (`arm64`) Mac'ler içindir ve henüz Apple tarafından notarize edilmemiştir. Bu nedenle macOS ilk açılışta “Apple, UsageBar öğesinin Mac'inize zarar verecek kötü amaçlı yazılım içermediğini doğrulayamadı” uyarısını gösterebilir. Aşağıdaki adımlar yalnızca bu depodaki resmi Release dosyasını indirdiyseniz uygulanmalıdır.

#### İlk açılışta macOS uyarısını onaylama

1. İndirdiğiniz ZIP'i açın ve `UsageBar.app` uygulamasını **Applications** klasörüne taşıyın.
2. UsageBar'ı bir kez açmayı deneyin.
3. Doğrulama uyarısı gelirse **Çöp Sepeti'ne Taşı** yerine **Bitti** düğmesine basın.
4. Apple menüsü  → **Sistem Ayarları** → **Gizlilik ve Güvenlik** bölümünü açın.
5. Aşağı kaydırıp **Güvenlik** bölümünde UsageBar'ın engellendiğini belirten mesajı bulun.
6. **Yine de Aç** düğmesine basın.
7. Touch ID veya Mac oturum parolanızla işlemi onaylayın ve sonraki pencerede **Aç** düğmesine basın.

Bu onay aynı uygulama için yalnızca ilk açılışta gerekir. **Yine de Aç** düğmesi görünmüyorsa UsageBar'ı tekrar açmayı deneyip aynı bölüme dönün; Apple bu seçeneği açma denemesinden sonra yaklaşık bir saat gösterir.

> [!CAUTION]
> Gatekeeper'ı tamamen kapatmayın ve internetteki rastgele `sudo`, `spctl` veya `xattr` komutlarını çalıştırmayın. Uyarıda uygulamanın bilinen kötü amaçlı yazılım içerdiği yazıyorsa devam etmeyin; dosyayı silip resmi Release'den yeniden indirin.

İndirdiğiniz dosyanın SHA-256 değerini Release sayfasındaki değerle karşılaştırmak isterseniz:

```sh
shasum -a 256 ~/Downloads/UsageBar-1.4.4-macOS-arm64.zip
```

v1.5.0 ve sonraki CI üretimi paketlerde GitHub build provenance kaydını da
doğrulayabilirsiniz:

```sh
gh attestation verify ~/Downloads/UsageBar-1.5.0-macOS-arm64.zip \
  --repo akwnnwastaken/UsageBar \
  --signer-workflow akwnnwastaken/UsageBar/.github/workflows/release-candidate.yml
```

SHA-256 dosyanın değişmediğini, attestation ise dosyanın bu deponun sabitlenmiş
GitHub Actions akışı tarafından üretildiğini doğrular. İkisini birlikte kontrol
etmek en güçlü ücretsiz doğrulamadır.

Apple'ın resmi açıklaması: [Apple'ın kötü amaçlı yazılım denetimi yapamadığı bir uygulamayı açma](https://support.apple.com/guide/mac-help/mchleab3a043/mac)

### Kullanım

1. UsageBar'ı açın.
2. Menü çubuğundaki `%—` simgesine tıklayın.
3. **Codex'e bağlan** veya **Claude Code'a bağlan** seçeneğini kullanın.
4. İki sağlayıcı da bağlıysa `Otomatik | Codex | Claude` anahtarıyla sabit bir sağlayıcı seçin veya 30 saniyelik otomatik geçişi açın.
5. `Üst çubuk görünümü`, `Kullanım renkleri` ve `Kullanım geçmişi` menülerinden görünümü isteğinize göre ayarlayın.
6. Sorun bildirirken kişisel veri içermeyen özeti almak için **Tanılama özetini kopyala** seçeneğini kullanın.

Bağlantı seçimi yalnızca yerel tercihi kaydeder. UsageBar şifre, erişim anahtarı veya oturum belirteci saklamaz.

Mini grafik açıksa UsageBar her sağlayıcı/pencere çifti için yalnızca ölçüm zamanı ile kalan yüzdeyi yerel uygulama tercihlerinde saklar. Başlangıçta grafik yalnızca gerçekten kaydedilmiş süreyi gösterir ve zamanla 24 saate ulaşır. Kayıtlar açılışta ve her yeni ölçümde 24 saat, seri sayısı ve örnek sayısı sınırlarına göre budanır; sağlayıcı yanıtları, komut çıktıları ve kimlik bilgileri geçmişe yazılmaz.

### Gizlilik ve macOS izinleri

UsageBar ilk açılışta hiçbir sağlayıcıya erişmez. Bir sağlayıcıyı ancak ilgili bağlantı düğmesine bastığınızda sorgular.

Uygulama şunlara ihtiyaç duymaz:

- Tam Disk Erişimi
- Belgeler veya Masaüstü erişimi
- Ağ diski erişimi
- Ekran Kaydı
- Erişilebilirlik
- Otomasyon

Claude Code bağlantısında macOS, mevcut `Claude Code-credentials` Anahtar Zinciri kaydı için izin isteyebilir. Sürekli sorulmaması için bu pencerede bir kez **Her Zaman İzin Ver** seçilebilir. Bunun dışındaki izin istekleri reddedilebilir.

**Mac açılışında başlat** seçeneği yalnızca macOS'un Giriş Öğeleri sistemini kullanır ve uygulama `/Applications` klasöründeyken kullanılmalıdır. macOS bu değişikliği bir sistem bildirimiyle gösterebilir veya Sistem Ayarları'ndan onay isteyebilir; ekran, disk veya otomasyon izni verilmez.

Sağlayıcı komutları uygulamaya özel geçici bir klasörde, küçük bir ortam değişkeni listesiyle ve ayrı süreç grubunda çalıştırılır. Proje ayarları, eklentiler, MCP sunucuları, Chrome entegrasyonu ve kabuk başlangıç ayarları yüklenmez. Zaman aşımında tüm çocuk süreç grubu kapatılır; çıktı 2 MiB ile sınırlandırılır. Çalıştırılabilir dosyaların gerçek symlink hedefi, sahibi ve yazma izinleri de kullanılmadan önce doğrulanır.

### Veri kaynakları

- **Codex:** Kurulu Codex aracının `account/rateLimits/read` yerel arayüzü.
- **Claude Code:** Claude Code'un resmi `rate_limits.five_hour` ve `rate_limits.seven_day` alanları; gerektiğinde `/usage` çıktısı yedek olarak kullanılır.

UsageBar sağlayıcıların web sitelerine kendi hesabıyla giriş yapmaz; bilgisayarınızdaki mevcut Codex ve Claude Code oturumlarını kullanır.

### Kaynak koddan derleme

```sh
git clone https://github.com/akwnnwastaken/UsageBar.git
cd UsageBar
chmod +x build.sh
./build.sh
open build/UsageBar.app
```

Derleme betiği kanonik SwiftPM grafiğiyle XCTest testlerini ve paket içi öz testleri çalıştırır; ardından temiz paketi yerel kullanım için ad hoc imzalar.

Paketleme regresyonunu da çalıştırmak için:

```sh
./tests/build_regression.sh
```

CI ile aynı tam güvenlik kabul kapısını çalıştırmak için:

```sh
./tests/security_acceptance.sh
```

### Proje yapısı

```text
UsageBar/
├── Sources/UsageBar/main.swift                 # Uygulama, arayüz ve sağlayıcı okuyucuları
├── Sources/UsageBarCore/Core.swift             # Saf, XCTest ile test edilen kurallar
├── Sources/UsageBarProcessLauncher/            # Shell kullanmayan süreç grubu başlatıcısı
├── tests/UsageBarCoreTests/                     # XCTest testleri
├── tests/build_regression.sh                    # Temiz paketleme ve imza regresyonu
├── tests/security_acceptance.sh                 # CI güvenlik kabul kapısı
├── .github/workflows/ci.yml                     # Paket ve güvenlik testleri
├── .github/workflows/codeql.yml                 # Manuel Swift CodeQL derlemesi
├── .github/workflows/release-candidate.yml      # İmzalı tag, SHA ve provenance üretimi
├── Package.swift                                # Kanonik SwiftPM derleme tanımı
├── Info.plist                     # macOS uygulama ve sürüm metadata'sı
├── build.sh                       # Derleme, test ve yerel imzalama
├── SECURITY.md                    # İki dilli güvenlik bildirim politikası
├── LICENSE                        # MIT Lisansı
└── README.md                      # Türkçe ve İngilizce dokümantasyon
```

### Geliştirme

Değişiklikler ayrı commitler ve pull requestler üzerinden ilerletilir. Böylece GitHub'daki commit geçmişinden önceki çalışan sürümlere dönülebilir ve her değişiklik ayrı ayrı incelenebilir.

Hassas bir güvenlik açığını herkese açık Issue yerine [güvenlik politikasındaki](SECURITY.md) özel bildirim adımlarıyla paylaşın.

### Lisans

UsageBar, [MIT Lisansı](LICENSE) ile sunulur.

---

## English

UsageBar is a small, local macOS menu bar app that displays Codex and Claude Code usage limits.

It shows the **remaining usage percentage** for the selected provider, together with its icon, directly in the menu bar. Open the detail menu to view usage windows, remaining percentages, and the time until each limit resets.

> [!NOTE]
> The `main` branch contains the source for the upcoming **v1.5.0** release. The latest downloadable package is currently **v1.4.4**; build from source to try the new features below until v1.5.0 is published.

### Features

- Tracks Codex and Claude Code usage in one app.
- Shows the remaining percentage for the selected provider's active usage window in the menu bar.
- Lists five-hour, weekly, and any other duration returned by the provider separately, showing only windows available on the account.
- Shows the reset countdown below the remaining percentage (`1h 15m`).
- Highlights the remaining percentage in green, orange, or red based on its level.
- Colors the menu-bar percentage orange or red at critical levels; colors can be disabled and three threshold profiles are available.
- Optionally shows the selected usage window's reset countdown in the menu bar.
- Switches the provider shown in the menu bar with the `Codex | Claude` selector.
- Rotates between Codex and Claude every 30 seconds when `Auto` is selected and both providers are connected.
- Shows up to 24 hours of remaining-percentage history separately for every usage window. It labels the actual recorded span, start/end values, and change; adaptive scaling exposes small movements and markers identify resets. Isolated one-sample ±1 point rounding fluctuations are smoothed only in the drawing.
- Keeps showing the last successful value with its timestamp and failure reason when a provider is temporarily unavailable; stale values are not recorded as new history samples.
- Copies a diagnostic summary containing only version, macOS, connection state, window kinds, and safe error codes. It excludes raw CLI output, file paths, and credentials.
- Can launch automatically at login through macOS Login Items.
- Selects Turkish or English from the macOS language on first launch and remembers the user's selection.
- Refreshes usage every five minutes and when the menu is reopened.
- Runs only in the menu bar without a Dock icon or main window.

### How is the percentage calculated?

The menu bar value is the **remaining percentage, not the used percentage**.

- **Claude Code:** Always shows the five-hour window when it is available, falling back to weekly usage only when five-hour data is missing.
- **Codex:** Shows the lowest remaining percentage among the windows available on the account. If the account exposes only a weekly window, UsageBar uses that window.

Open the menu to see every window returned by the selected provider.

### Requirements

- macOS 13 or later
- The ChatGPT app or a signed-in Codex CLI installation for Codex tracking
- A signed-in Claude Code CLI installation for Claude tracking
- Xcode Command Line Tools only when building from source

You only need to install the provider you want to track.

### Download and install

1. Download the latest `macOS-arm64.zip` file from [Releases](https://github.com/akwnnwastaken/UsageBar/releases).
2. Extract the ZIP and move `UsageBar.app` to the **Applications** folder.
3. Open UsageBar and connect a provider from the `%—` icon in the menu bar.

> [!WARNING]
> The current Beta package supports Apple Silicon (`arm64`) Macs and has not yet been notarized by Apple. macOS may therefore report that Apple could not verify UsageBar is free of malware. Follow the steps below only if you downloaded the official Release file from this repository.

#### Approving the macOS warning on first launch

1. Extract the downloaded ZIP and move `UsageBar.app` to the **Applications** folder.
2. Try to open UsageBar once.
3. When the verification warning appears, click **Done** instead of **Move to Bin**.
4. Open Apple menu  → **System Settings** → **Privacy & Security**.
5. Scroll to the **Security** section and find the message stating that UsageBar was blocked.
6. Click **Open Anyway**.
7. Authenticate with Touch ID or your Mac login password, then click **Open** in the confirmation dialog.

This approval is required only on the first launch of the same app. If **Open Anyway** is missing, try to open UsageBar again and return to Privacy & Security. Apple makes this option available for about one hour after the launch attempt.

> [!CAUTION]
> Do not disable Gatekeeper globally or run arbitrary `sudo`, `spctl`, or `xattr` commands from the internet. If macOS reports that the app contains known malware, do not continue; delete the file and download it again from the official Release.

To compare the downloaded file's SHA-256 value with the value published on the Release page:

```sh
shasum -a 256 ~/Downloads/UsageBar-1.4.4-macOS-arm64.zip
```

For v1.5.0 and later CI-produced packages, you can also verify GitHub build
provenance:

```sh
gh attestation verify ~/Downloads/UsageBar-1.5.0-macOS-arm64.zip \
  --repo akwnnwastaken/UsageBar \
  --signer-workflow akwnnwastaken/UsageBar/.github/workflows/release-candidate.yml
```

SHA-256 verifies that the file did not change; the attestation verifies that it
was produced by this repository's pinned GitHub Actions workflow. Checking both
provides the strongest free verification available for the current release.

Apple's official instructions: [Open an app Apple cannot check for malicious software](https://support.apple.com/guide/mac-help/mchleab3a043/mac)

### Usage

1. Open UsageBar.
2. Click the `%—` icon in the menu bar.
3. Choose **Connect Codex** or **Connect Claude Code**.
4. If both providers are connected, use `Auto | Codex | Claude` to pin one provider or enable 30-second automatic rotation.
5. Customize the display through the `Menu bar appearance`, `Usage colors`, and `Usage history` menus.
6. When reporting a problem, use **Copy diagnostics** to obtain a summary without personal data.

Connecting a provider only saves a local preference. UsageBar does not store passwords, API keys, access tokens, or session tokens.

When the mini chart is enabled, UsageBar stores only the measurement time and remaining percentage for each provider/window pair in local app preferences. The chart initially shows only the span actually recorded and grows toward 24 hours. Data is pruned on launch and after every measurement using 24-hour, series-count, and sample-count limits; provider responses, command output, and credentials are never written to history.

### Privacy and macOS permissions

UsageBar does not access either provider on first launch. It queries a provider only after you explicitly click its connection button.

The app does not require:

- Full Disk Access
- Documents or Desktop access
- Network volume access
- Screen Recording
- Accessibility
- Automation

When connecting Claude Code, macOS may request access to the existing `Claude Code-credentials` Keychain item. Choose **Always Allow** once if you do not want the prompt to reappear. Other unrelated permission requests can be denied.

The **Launch at login** option uses only the macOS Login Items system and should be enabled while the app is in `/Applications`. macOS may show a system notification or require approval in System Settings; no screen, disk, or automation permission is granted.

Provider commands run in an app-specific temporary directory with a small environment and a separate process group. Project settings, plugins, MCP servers, Chrome integration, and shell startup files are not loaded. Timeouts terminate the entire child process group and output is limited to 2 MiB. Resolved symlink targets, ownership, and write permissions of provider executables are validated before use.

### Data sources

- **Codex:** The installed Codex tool's local `account/rateLimits/read` interface.
- **Claude Code:** Claude Code's official `rate_limits.five_hour` and `rate_limits.seven_day` fields, with `/usage` output used as a fallback when needed.

UsageBar does not sign in to provider websites itself. It uses the existing local Codex and Claude Code sessions on the Mac.

### Build from source

```sh
git clone https://github.com/akwnnwastaken/UsageBar.git
cd UsageBar
chmod +x build.sh
./build.sh
open build/UsageBar.app
```

The build script uses the canonical SwiftPM graph, runs XCTest and packaged-binary self-tests, then applies an ad hoc signature to the clean bundle for local use.

To run the packaging regression as well:

```sh
./tests/build_regression.sh
```

To run the same complete security acceptance gate as CI:

```sh
./tests/security_acceptance.sh
```

### Project structure

```text
UsageBar/
├── Sources/UsageBar/main.swift                 # Application, UI, and provider readers
├── Sources/UsageBarCore/Core.swift             # Pure rules covered by XCTest
├── Sources/UsageBarProcessLauncher/            # Shell-free process-group launcher
├── tests/UsageBarCoreTests/                     # XCTest suite
├── tests/build_regression.sh                    # Clean packaging and signature regression
├── tests/security_acceptance.sh                 # CI security acceptance gate
├── .github/workflows/ci.yml                     # Packaging and security checks
├── .github/workflows/codeql.yml                 # Manual Swift CodeQL build
├── .github/workflows/release-candidate.yml      # Signed tag, SHA, and provenance build
├── Package.swift                                # Canonical SwiftPM build graph
├── Info.plist                     # macOS application and version metadata
├── build.sh                       # Build, test, and local signing
├── SECURITY.md                    # Bilingual vulnerability reporting policy
├── LICENSE                        # MIT License
└── README.md                      # Turkish and English documentation
```

### Development

Changes are developed through separate commits and pull requests. This keeps each change reviewable and makes it possible to return to earlier working versions through Git history.

Report sensitive vulnerabilities through the private process in the [security policy](SECURITY.md), not a public Issue.

### License

UsageBar is available under the [MIT License](LICENSE).
