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
- 5 saatlik ve haftalık pencereleri ayrı ayrı listeler; yalnızca hesapta bulunan pencereleri gösterir.
- Sıfırlama zamanını yüzde bilgisinin altında gösterir (`1sa 15dk` / `1h 15m`).
- Kalan oranı seviyesine göre yeşil, turuncu veya kırmızı renklendirir.
- Menü çubuğundaki yüzdeyi kritik seviyelerde turuncu veya kırmızı gösterir; renkler kapatılabilir ve üç farklı eşik profili seçilebilir.
- İstenirse menü çubuğunda seçili kullanım penceresinin sıfırlanma sayacını da gösterir.
- Üst çubukta gösterilecek sağlayıcıyı `Codex | Claude` anahtarıyla değiştirir.
- İki sağlayıcı bağlıyken `Otomatik` moduyla Codex ve Claude arasında 30 saniyede bir geçiş yapar.
- Her sağlayıcının 24 saate kadar kalan yüzde geçmişini yerel bir mini grafikte gösterir. Grafik gerçek kayıt aralığını, başlangıç/bitiş yüzdelerini ve değişimi yazar; küçük hareketleri uyarlanabilir ölçekle, sıfırlanmaları işaretlerle görünür kılar. Tek ölçümlük ±1 puan yuvarlama dalgalanmaları yalnızca çizimde yumuşatılır.
- macOS Giriş Öğeleri üzerinden Mac açılışında otomatik başlatılabilir.
- Türkçe ve İngilizce arayüz sunar; seçimleri sonraki açılışlar için saklar.
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

Apple'ın resmi açıklaması: [Apple'ın kötü amaçlı yazılım denetimi yapamadığı bir uygulamayı açma](https://support.apple.com/guide/mac-help/mchleab3a043/mac)

### Kullanım

1. UsageBar'ı açın.
2. Menü çubuğundaki `%—` simgesine tıklayın.
3. **Codex'e bağlan** veya **Claude Code'a bağlan** seçeneğini kullanın.
4. İki sağlayıcı da bağlıysa `Otomatik | Codex | Claude` anahtarıyla sabit bir sağlayıcı seçin veya 30 saniyelik otomatik geçişi açın.
5. `Üst çubuk görünümü`, `Kullanım renkleri` ve `Kullanım geçmişi` menülerinden görünümü isteğinize göre ayarlayın.

Bağlantı seçimi yalnızca yerel tercihi kaydeder. UsageBar şifre, erişim anahtarı veya oturum belirteci saklamaz.

Mini grafik açıksa UsageBar yalnızca ölçüm zamanı ile kalan yüzdeyi yerel uygulama tercihlerinde saklar. Başlangıçta grafik yalnızca gerçekten kaydedilmiş süreyi gösterir ve zamanla 24 saate ulaşır. Kayıtlar 24 saat sonra otomatik silinir; sağlayıcı yanıtları, komut çıktıları ve kimlik bilgileri geçmişe yazılmaz.

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

Sağlayıcı komutları uygulamaya özel geçici bir klasörde çalıştırılır. Proje ayarları, eklentiler, MCP sunucuları, Chrome entegrasyonu ve kabuk başlangıç ayarları yüklenmez.

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

Derleme betiği uygulamayı oluşturur; parser, yerelleştirme, pencere önceliği, renk eşikleri, geçmiş ve sağlayıcı dönüşümü öz testlerini çalıştırır; ardından temiz paketi yerel kullanım için ad hoc imzalar.

Paketleme regresyonunu da çalıştırmak için:

```sh
./tests/build_regression.sh
```

### Proje yapısı

```text
UsageBar/
├── Sources/UsageBar/main.swift    # Uygulama, arayüz, veri okuyucuları ve öz testler
├── tests/build_regression.sh      # Temiz paketleme ve imza regresyonu
├── .github/workflows/ci.yml       # GitHub Actions derleme kontrolü
├── Package.swift                  # SwiftPM ve CodeQL derleme tanımı
├── Info.plist                     # macOS uygulama ve sürüm metadata'sı
├── build.sh                       # Derleme, test ve yerel imzalama
├── LICENSE                        # MIT Lisansı
└── README.md                      # Türkçe ve İngilizce dokümantasyon
```

### Geliştirme

Değişiklikler ayrı commitler ve pull requestler üzerinden ilerletilir. Böylece GitHub'daki commit geçmişinden önceki çalışan sürümlere dönülebilir ve her değişiklik ayrı ayrı incelenebilir.

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
- Lists five-hour and weekly windows separately and only displays windows available on the account.
- Shows the reset countdown below the remaining percentage (`1h 15m`).
- Highlights the remaining percentage in green, orange, or red based on its level.
- Colors the menu-bar percentage orange or red at critical levels; colors can be disabled and three threshold profiles are available.
- Optionally shows the selected usage window's reset countdown in the menu bar.
- Switches the provider shown in the menu bar with the `Codex | Claude` selector.
- Rotates between Codex and Claude every 30 seconds when `Auto` is selected and both providers are connected.
- Shows up to 24 hours of each provider's remaining-percentage history in a local mini chart. It labels the actual recorded span, start/end values, and change; adaptive scaling exposes small movements and markers identify resets. Isolated one-sample ±1 point rounding fluctuations are smoothed only in the drawing.
- Can launch automatically at login through macOS Login Items.
- Includes Turkish and English interfaces and remembers the selected language.
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

Apple's official instructions: [Open an app Apple cannot check for malicious software](https://support.apple.com/guide/mac-help/mchleab3a043/mac)

### Usage

1. Open UsageBar.
2. Click the `%—` icon in the menu bar.
3. Choose **Connect Codex** or **Connect Claude Code**.
4. If both providers are connected, use `Auto | Codex | Claude` to pin one provider or enable 30-second automatic rotation.
5. Customize the display through the `Menu bar appearance`, `Usage colors`, and `Usage history` menus.

Connecting a provider only saves a local preference. UsageBar does not store passwords, API keys, access tokens, or session tokens.

When the mini chart is enabled, UsageBar stores only the measurement time and remaining percentage in local app preferences. The chart initially shows only the span actually recorded and grows toward 24 hours. Samples expire automatically after 24 hours; provider responses, command output, and credentials are never written to history.

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

Provider commands run in an app-specific temporary directory. Project settings, plugins, MCP servers, Chrome integration, and shell startup files are not loaded.

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

The build script compiles the app; runs built-in tests for parsing, localization, window priority, color thresholds, history, and provider rotation; then applies an ad hoc signature to the clean bundle for local use.

To run the packaging regression as well:

```sh
./tests/build_regression.sh
```

### Project structure

```text
UsageBar/
├── Sources/UsageBar/main.swift    # Application, UI, usage readers, and self-tests
├── tests/build_regression.sh      # Clean packaging and signature regression
├── .github/workflows/ci.yml       # GitHub Actions build check
├── Package.swift                  # SwiftPM and CodeQL build definition
├── Info.plist                     # macOS application and version metadata
├── build.sh                       # Build, test, and local signing
├── LICENSE                        # MIT License
└── README.md                      # Turkish and English documentation
```

### Development

Changes are developed through separate commits and pull requests. This keeps each change reviewable and makes it possible to return to earlier working versions through Git history.

### License

UsageBar is available under the [MIT License](LICENSE).
