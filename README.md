# UsageBar

[Türkçe](#türkçe) · [English](#english)

## Türkçe

Codex ve Claude Code kullanım limitlerini macOS menü çubuğunda ve Windows sistem tepsisinde gösteren küçük ve yerel bir uygulama.

UsageBar, seçtiğiniz sağlayıcının **kalan kullanım oranını** simgesiyle birlikte macOS menü çubuğunda veya Windows sistem tepsisinde gösterir. Ayrıntı panelinde kullanım pencerelerini, kalan yüzdeleri ve sıfırlanmaya kalan süreyi görebilirsiniz.

### Sürümler

Sürüm **1.9.0** her iki platformda da güncel sürümdür. İki platformun kendi etiketi ve kendi Release sayfası vardır; aynı etiket değildirler.

| Platform | Sürüm | İndirme |
| --- | --- | --- |
| macOS — Apple Silicon | 1.9.0 | [v1.9.0](https://github.com/akwnnwastaken/UsageBar/releases/tag/v1.9.0) |
| Windows — x64 | 1.9.0 | [windows-v1.9.0](https://github.com/akwnnwastaken/UsageBar/releases/tag/windows-v1.9.0) |

`main` dalı her iki sürümün de kaynak kodunu içerir.

### Özellikler

- Codex ve Claude Code kullanımını tek uygulamada izler.
- Menü çubuğunda veya sistem tepsisinde, seçili sağlayıcının aktif kullanım penceresine ait kalan oranı gösterir.
- 5 saatlik, haftalık ve sağlayıcının döndürdüğü diğer süreli pencereleri ayrı ayrı listeler; yalnızca hesapta bulunan pencereleri gösterir.
- Sıfırlama zamanını yüzde bilgisinin altında gösterir (`1sa 15dk` / `1h 15m`).
- Kalan oranı seviyesine göre yeşil, turuncu veya kırmızı renklendirir.
- Simgedeki yüzdeyi kritik seviyelerde turuncu veya kırmızı gösterir; renkler kapatılabilir ve üç farklı eşik profili seçilebilir.
- Gösterilecek sağlayıcıyı `Codex | Claude` anahtarıyla değiştirir; iki sağlayıcı bağlıyken `Otomatik` moduyla 30 saniyede bir geçiş yapar.
- Her bağlı sağlayıcıyı menüden bağlantıdan kaldırabilir; bu, kullanım geçmişini silmez.
- Her kullanım penceresinin kalan yüzde geçmişini (24 saate kadar) ayrı bir **yerel** mini grafikte gösterir. Grafik, mevcut pencerenin arkını net göstermek için **son sıfırlamadan itibaren** çizilir: pencere her sıfırlandığında (kalan oran yaklaşık %100'e döndüğünde) grafik baştan başlar. Gösterilen kayıt aralığını, başlangıç/bitiş yüzdelerini ve değişimi yazar; küçük hareketleri uyarlanabilir ölçekle görünür kılar. Bir pencere içinde kalan oran gerçekte artamaz; yine de sağlayıcı yüzdeyi tam sayıya yuvarladığı için değer 41 ↔ 42 gibi oynayabilir ve yeni açılan bir okuma oturumu bazen sunucuda önbelleğe alınmış, canlı değerin gerisinde kalan eski bir anlık değer alıp 33 → 38 gibi sahte bir geri sıçrama gösterebilir. Arayüzdeki değer, sıfırlama eşiğinin altındaki bu yükselişleri birkaç ölçüm boyunca doğrulanmadıkça göstermez; böylece hem yuvarlama dalgalanmaları hem de eski anlık değer geri sıçramaları gizlenir. Sıfırlamalar (yaklaşık %100'e büyük sıçrama) anında yansır ve kaydedilen geçmiş her zaman ham kalır.
- Sağlayıcı geçici olarak yanıt vermezse son başarılı değeri zamanı ve hata nedeni ile eski veri olarak göstermeye devam eder; eski ölçüm geçmişe yeniden yazılmaz.
- Sürüm, işletim sistemi sürümü, bağlantı durumu, pencere türleri ve güvenli hata kodlarından oluşan bir **tanılama özetini** panoya kopyalar. Ham CLI çıktısı, dosya yolu, kullanıcı adı veya kimlik bilgisi eklemez.
- Oturum açıldığında otomatik başlatılabilir (isteğe bağlı).
- İlk açılışta işletim sistemi diline göre Türkçe veya İngilizce arayüz seçer; kullanıcı seçimini sonraki açılışlar için saklar.
- Kullanım verisini seçilebilir aralıklarla (1, 2 veya 5 dakika; varsayılan 5) ve panel açıldığında veri 30 saniyeden eskiyse yeniler.

#### Platform notları

İki platform aynı kuralları paylaşır, ancak uygulanışları farklıdır.

**macOS**

- Dock simgesi veya ana pencere açmadan yalnızca menü çubuğunda çalışır.
- Otomatik başlatma macOS **Giriş Öğeleri** sistemini kullanır.
- Codex için ChatGPT uygulaması veya kurulu Codex CLI, Claude için kurulu Claude Code CLI okunur.
- Sağlayıcı komutları ayrı bir süreç grubunda çalıştırılır.

**Windows**

- Yerel bir **C# / .NET 8 / WPF** sistem tepsisi uygulamasıdır; görev çubuğu düğmesi veya ana pencere açmaz.
- Codex'in resmî Windows kurulumu desteklenir.
- Claude Code'un yerel Windows kurulumu desteklenir.
- Claude Code'un **WSL** üzerinden okunması desteklenir, ancak 1.9.0 sürümünde fiziksel olarak doğrulanmamıştır.
- **Taşınabilir ZIP** ve **kullanıcıya özel kurulum paketi** olarak dağıtılır.
- Kurulum paketi yönetici izni istemez.
- Kurulum paketi UsageBar'ı **bilerek otomatik başlatmaz**; kurulumdan sonra uygulama Başlat menüsünden açılır.
- Otomatik başlatma tercihi UsageBar'a aittir ve yalnızca geçerli kullanıcının ayarlarında tutulur.
- Sağlayıcı süreçleri `CreateProcessW` ile başlatılır ve bir **Job Object** içinde sınırlandırılır; çıktı sınırlıdır.
- Kabuk (shell) yedeği, servis, sürücü, zamanlanmış görev veya `PATH` değişikliği yoktur.

### Yüzde nasıl hesaplanıyor?

Simgedeki değer **kullanılan değil, kalan yüzdedir**.

- **Claude Code:** 5 saatlik pencere varsa her zaman onu gösterir. Bu veri yoksa haftalık pencereye geri döner.
- **Codex:** Hesabın sunduğu pencereler arasından en düşük kalan oranı gösterir. Hesap yalnızca haftalık pencere sunuyorsa onu kullanır.

Simgeye tıkladığınızda sağlayıcının sunduğu tüm pencereleri ayrı ayrı görebilirsiniz.

### Gereksinimler

Yalnızca kullanmak istediğiniz sağlayıcının kurulu olması yeterlidir.

#### macOS

- macOS 13 veya daha yeni
- Apple Silicon (`arm64`)
- Codex için ChatGPT uygulaması veya giriş yapılmış Codex CLI
- Claude için giriş yapılmış Claude Code CLI
- Kaynak koddan derlemek için Xcode Command Line Tools

#### Windows

- Windows 10 sürüm 1809 veya daha yeni (Windows 11 dahil)
- x64 işlemci ve işletim sistemi
- Codex için giriş yapılmış resmî Windows Codex kurulumu
- Claude için giriş yapılmış yerel Claude Code kurulumu
- WSL Claude desteği mevcut ancak 1.9.0 sürümünde fiziksel olarak doğrulanmadı
- Son kullanıcı için ayrıca .NET Runtime kurulumu gerekmez; paket self-contained'dır
- Kaynak koddan derlemek için .NET 8 SDK

### İndir ve kur — macOS

1. [v1.9.0](https://github.com/akwnnwastaken/UsageBar/releases/tag/v1.9.0) sürümünden `macOS-arm64.zip` dosyasını indirin.
2. ZIP dosyasını açın ve `UsageBar.app` uygulamasını **Applications** klasörüne taşıyın.
3. UsageBar'ı açın; menü çubuğundaki `%—` simgesinden sağlayıcınızı bağlayın.

> [!WARNING]
> Bu paket Apple Silicon (`arm64`) Mac'ler içindir ve henüz Apple tarafından notarize edilmemiştir. Bu nedenle macOS ilk açılışta “Apple, UsageBar öğesinin Mac'inize zarar verecek kötü amaçlı yazılım içermediğini doğrulayamadı” uyarısını gösterebilir. Aşağıdaki adımlar yalnızca bu depodaki resmi Release dosyasını indirdiyseniz uygulanmalıdır.

#### İlk açılışta macOS uyarısını onaylama

1. İndirdiğiniz ZIP'i açın ve `UsageBar.app` uygulamasını **Applications** klasörüne taşıyın.
2. UsageBar'ı bir kez açmayı deneyin.
3. Doğrulama uyarısı gelirse **Çöp Sepeti'ne Taşı** yerine **Bitti** düğmesine basın.
4. Apple menüsü  → **Sistem Ayarları** → **Gizlilik ve Güvenlik** bölümünü açın.
5. Aşağı kaydırıp **Güvenlik** bölümünde UsageBar'ın engellendiğini belirten mesajı bulun.
6. **Yine de Aç** düğmesine basın.
7. Touch ID veya Mac oturum parolanızla işlemi onaylayın ve sonraki pencerede **Aç** düğmesine basın.

Bu onay aynı uygulama için yalnızca ilk açılışta gerekir. **Yine de Aç** düğmesi görünmüyorsa UsageBar'ı tekrar açmayı deneyip aynı bölüme dönün; Apple bu seçeneği açma denemesinden sonra yaklaşık bir saat gösterir.

> [!CAUTION]
> Gatekeeper'ı tamamen kapatmayın ve internetteki rastgele `sudo`, `spctl` veya `xattr` komutlarını çalıştırmayın. Uyarıda uygulamanın bilinen kötü amaçlı yazılım içerdiği yazıyorsa devam etmeyin; dosyayı silip resmi Release'den yeniden indirin.

#### macOS dosya doğrulama

İndirdiğiniz dosyanın SHA-256 değerini Release sayfasındaki değerle karşılaştırmak isterseniz:

```sh
shasum -a 256 ~/Downloads/UsageBar-1.9.0-macOS-arm64.zip
```

CI tarafından üretilen paketlerde GitHub build provenance kaydını da doğrulayabilirsiniz:

```sh
gh attestation verify ~/Downloads/UsageBar-1.9.0-macOS-arm64.zip \
  --repo akwnnwastaken/UsageBar \
  --signer-workflow akwnnwastaken/UsageBar/.github/workflows/release-candidate.yml
```

SHA-256 dosyanın değişmediğini, attestation ise dosyanın bu deponun sabitlenmiş GitHub Actions akışı tarafından üretildiğini doğrular. İkisini birlikte kontrol etmek en güçlü ücretsiz doğrulamadır.

Apple'ın resmi açıklaması: [Apple'ın kötü amaçlı yazılım denetimi yapamadığı bir uygulamayı açma](https://support.apple.com/guide/mac-help/mchleab3a043/mac)

### İndir ve kur — Windows

#### Kurulum paketi (önerilen)

1. [windows-v1.9.0](https://github.com/akwnnwastaken/UsageBar/releases/tag/windows-v1.9.0) sürümünü açın.
2. `UsageBar-Setup-x64.exe` dosyasını indirin.
3. İsterseniz yanındaki `.sha256` dosyasıyla doğrulayın (aşağıya bakın).
4. Kurulum paketini çalıştırın. Yönetici izni istenmez; kurulum yalnızca geçerli kullanıcı içindir.
5. **Kurulum paketi UsageBar'ı otomatik başlatmaz.** Bu bilinçli bir tercihtir.
6. Başlat menüsünü açın, `UsageBar` yazın ve uygulamayı seçin.
7. UsageBar sistem tepsisinde çalışır.
8. Simge görünmüyorsa görev çubuğundaki `^` taşma alanını kontrol edin.

> [!WARNING]
> Bu kurulum paketi henüz imzalanmamıştır. Windows SmartScreen bir uyarı gösterebilir. Devam etmeden önce dosyanın SHA-256 değerini Release sayfasındaki değerle karşılaştırın. SmartScreen'i sistem genelinde kapatmayın.

#### Taşınabilir sürüm

1. `UsageBar-Windows-x64.zip` dosyasını indirin.
2. Kalıcı ve yazılabilir bir klasöre çıkarın.
3. Uygulamayı doğrudan ZIP dosyasının içinden çalıştırmayın.
4. `UsageBar.exe` dosyasını çalıştırın.

#### Windows dosya doğrulama

PowerShell'de, indirdiğiniz dosyanın bulunduğu klasörde:

```powershell
Get-FileHash .\UsageBar-Setup-x64.exe -Algorithm SHA256
Get-FileHash .\UsageBar-Windows-x64.zip -Algorithm SHA256
```

Çıkan değeri, aynı Release sayfasındaki `.sha256` dosyasıyla ve Release notlarındaki değerle karşılaştırın. Üçü de aynı olmalıdır.

### Kullanım

1. UsageBar'ı açın. Windows'ta kurulum paketini kullandıysanız uygulamayı ilk kez Başlat menüsünden açın.
2. macOS'ta menü çubuğundaki, Windows'ta sistem tepsisindeki `%—` simgesine tıklayın.
3. **Codex'e bağlan** veya **Claude Code'a bağlan** seçeneğini kullanın.
4. İki sağlayıcı da bağlıysa `Otomatik | Codex | Claude` anahtarıyla sabit bir sağlayıcı seçin veya 30 saniyelik otomatik geçişi açın.
5. Görünüm, kullanım renkleri, kullanım geçmişi ve yenileme aralığı ayarlarından görünümü ve tazeleme sıklığını isteğinize göre ayarlayın.
6. Sorun bildirirken kişisel veri içermeyen özeti almak için **Tanılama özetini kopyala** seçeneğini kullanın.

Bağlantı seçimi yalnızca yerel bir tercihi kaydeder. UsageBar şifre, erişim anahtarı veya oturum belirteci saklamaz.

Mini grafik açıksa UsageBar her sağlayıcı/pencere çifti için yalnızca ölçüm zamanı ile kalan yüzdeyi yerel olarak saklar. Başlangıçta grafik yalnızca gerçekten kaydedilmiş süreyi gösterir ve zamanla 24 saate ulaşır. Kayıtlar açılışta ve her yeni ölçümde 24 saat, seri sayısı ve örnek sayısı sınırlarına göre budanır; sağlayıcı yanıtları, komut çıktıları ve kimlik bilgileri geçmişe yazılmaz.

### Gizlilik ve izinler

UsageBar ilk açılışta hiçbir sağlayıcıya erişmez. Bir sağlayıcıyı ancak ilgili bağlantı düğmesine bastığınızda sorgular.

Sağlayıcı komutları uygulamaya özel geçici bir klasörde, küçük bir ortam değişkeni listesiyle çalıştırılır. Proje ayarları, eklentiler, MCP sunucuları, Chrome entegrasyonu ve kabuk başlangıç ayarları yüklenmez. Zaman aşımında tüm çocuk süreçler kapatılır ve çıktı 2 MiB ile sınırlandırılır. Çalıştırılabilir dosyalar kullanılmadan önce doğrulanır.

#### macOS

Uygulama şunlara ihtiyaç duymaz:

- Tam Disk Erişimi
- Belgeler veya Masaüstü erişimi
- Ağ diski erişimi
- Ekran Kaydı
- Erişilebilirlik
- Otomasyon

Claude Code bağlantısında macOS, mevcut `Claude Code-credentials` Anahtar Zinciri kaydı için izin isteyebilir. Sürekli sorulmaması için bu pencerede bir kez **Her Zaman İzin Ver** seçilebilir. Bunun dışındaki izin istekleri reddedilebilir.

**Mac açılışında başlat** seçeneği yalnızca macOS'un Giriş Öğeleri sistemini kullanır ve uygulama `/Applications` klasöründeyken kullanılmalıdır. macOS bu değişikliği bir sistem bildirimiyle gösterebilir veya Sistem Ayarları'ndan onay isteyebilir; ekran, disk veya otomasyon izni verilmez.

Sağlayıcı komutları ayrı bir süreç grubunda çalıştırılır; çalıştırılabilir dosyaların gerçek symlink hedefi, sahibi ve yazma izinleri kullanılmadan önce doğrulanır.

#### Windows

- Kurulum paketi yönetici izni istemez.
- Servis veya sürücü kurulmaz.
- Zamanlanmış görev oluşturulmaz.
- `PATH` değiştirilmez.
- Telemetri veya çökme raporlama bağımlılığı yoktur.
- Sağlayıcı çalıştırılabilir dosyaları kullanılmadan önce doğrulanır.
- Sağlayıcı süreçleri bir Job Object içinde sınırlandırılır ve çıktıları sınırlıdır.
- UsageBar sağlayıcı parolalarını, erişim belirteçlerini veya ham komut çıktısını geçmiş olarak saklamaz.

Otomatik başlatma tercihi UsageBar'a aittir ve yalnızca geçerli kullanıcının ayarlarında tutulur; kurulum paketi bu tercihi ne oluşturur ne de siler.

### Veri kaynakları

- **Codex:** Kurulu Codex aracının `account/rateLimits/read` yerel arayüzü.
- **Claude Code:** Claude Code'un yerel kullanım komutunun çıktısı. Bu, oturum kaydı bırakmayan, model kotası tüketmeyen yerel bir komuttur.

UsageBar sağlayıcıların web sitelerine kendi hesabıyla giriş yapmaz; bilgisayarınızdaki mevcut Codex ve Claude Code oturumlarını kullanır.

### Kaynak koddan derleme

#### macOS

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

#### Windows

Windows tarafı ayrı bir .NET çözümüdür ve macOS `build.sh` akışını kullanmaz. Komutlar `windows/` klasöründen çalıştırılmalıdır: SDK sürümü oradaki `global.json` ile .NET 8'e sabitlenmiştir.

```powershell
git clone https://github.com/akwnnwastaken/UsageBar.git
cd UsageBar/windows
dotnet restore UsageBar.Windows.sln
dotnet build UsageBar.Windows.sln --configuration Release --no-restore
dotnet test UsageBar.Windows.sln --configuration Release
```

Uygulamayı doğrudan çalıştırmak için:

```powershell
dotnet run --project src/UsageBar.Windows.App/UsageBar.Windows.App.csproj -c Release
```

Taşınabilir paketi ve kurulum paketini üretmek için:

```powershell
./scripts/package.ps1
./scripts/package-installer.ps1
```

`package.ps1` self-contained taşınabilir ZIP'i, `package-installer.ps1` ise Inno Setup ile kurulum paketini üretir. Üretilen paketleri CI ile aynı kapılardan geçirmek için:

```powershell
./scripts/verify-package.ps1
./scripts/verify-installer.ps1
```

`Core` ve `Core.Tests` projeleri `net8.0` hedefler ve her platformda derlenip çalışır; Windows'a özel testler diğer platformlarda atlanır. Ayrıntılar için [`docs/windows-port.md`](docs/windows-port.md) dosyasına bakın.

### Proje yapısı

```text
UsageBar/
├── Sources/UsageBar/main.swift             # macOS uygulaması, arayüzü ve sağlayıcı okuyucuları
├── Sources/UsageBarCore/Core.swift         # Saf, XCTest ile test edilen kurallar
├── Sources/UsageBarProcessLauncher/        # Shell kullanmayan süreç grubu başlatıcısı
├── Package.swift                           # Kanonik SwiftPM derleme tanımı
├── Info.plist                              # macOS uygulama ve sürüm metadata'sı
├── build.sh                                # macOS derleme, test ve yerel imzalama
├── tests/                                  # XCTest testleri ve macOS kabul betikleri
├── windows/
│   ├── UsageBar.Windows.sln                # Windows çözümü
│   ├── Directory.Build.props               # Ortak sürüm ve derleyici ayarları
│   ├── global.json                         # .NET 8 SDK sabitlemesi
│   ├── src/                                # Core, Infrastructure ve WPF tepsi uygulaması
│   ├── tests/                              # xUnit testleri
│   ├── scripts/                            # Paketleme, kurulum ve doğrulama betikleri
│   └── installer/                          # Inno Setup tanımı ve uygulama simgesi
├── shared/fixtures/                        # İki platformun paylaştığı sağlayıcı örnek çıktıları
├── docs/windows-port.md                    # Windows portunun tasarım ve doğrulama notları
├── .github/workflows/ci.yml                # macOS paket ve güvenlik testleri
├── .github/workflows/windows-ci.yml        # Windows derleme, test ve paketleme kapıları
├── .github/workflows/release-candidate.yml # İmzalı tag, SHA ve provenance üretimi
├── SECURITY.md                             # İki dilli güvenlik bildirim politikası
├── LICENSE                                 # MIT Lisansı
└── README.md                               # Türkçe ve İngilizce dokümantasyon
```

### Geliştirme

Değişiklikler ayrı commitler ve pull requestler üzerinden ilerletilir. Böylece GitHub'daki commit geçmişinden önceki çalışan sürümlere dönülebilir ve her değişiklik ayrı ayrı incelenebilir.

Hassas bir güvenlik açığını herkese açık Issue yerine [güvenlik politikasındaki](SECURITY.md) özel bildirim adımlarıyla paylaşın.

### Lisans

UsageBar, [MIT Lisansı](LICENSE) ile sunulur.

---

## English

A small, local app that displays Codex and Claude Code usage limits in the macOS menu bar and Windows system tray.

UsageBar shows the **remaining usage percentage** for the selected provider, together with its icon, in the macOS menu bar or the Windows system tray. Open the detail panel to view usage windows, remaining percentages, and the time until each limit resets.

### Releases

Version **1.9.0** is current on both platforms. Each platform has its own tag and its own Release page; they are not the same tag.

| Platform | Version | Download |
| --- | --- | --- |
| macOS — Apple Silicon | 1.9.0 | [v1.9.0](https://github.com/akwnnwastaken/UsageBar/releases/tag/v1.9.0) |
| Windows — x64 | 1.9.0 | [windows-v1.9.0](https://github.com/akwnnwastaken/UsageBar/releases/tag/windows-v1.9.0) |

The `main` branch contains the source for both.

### Features

- Tracks Codex and Claude Code usage in one app.
- Shows the remaining percentage for the selected provider's active usage window in the menu bar or system tray.
- Lists five-hour, weekly, and any other duration returned by the provider separately, showing only windows available on the account.
- Shows the reset countdown below the remaining percentage (`1h 15m`).
- Highlights the remaining percentage in green, orange, or red based on its level.
- Colors the icon percentage orange or red at critical levels; colors can be disabled and three threshold profiles are available.
- Switches the displayed provider with the `Codex | Claude` selector, and rotates between them every 30 seconds when `Auto` is selected and both are connected.
- Can disconnect any connected provider from the menu; this does not delete the usage history.
- Shows remaining-percentage history (up to 24 hours) separately for every usage window, in a **local** mini chart. To make the current window a clean arc, the chart is drawn **from the last reset onward**: each time the window resets (remaining returns to ~100%), the chart starts over. It labels the shown span, start/end values, and change, and adaptive scaling exposes small movements. Remaining cannot genuinely rise inside a window, yet the value can flicker between 41 and 42 because the provider rounds to a whole number, and a freshly spawned reader session can occasionally return a server-cached snapshot that lags the live value, showing a spurious rebound such as 33 → 38. The interface withholds any rise below the reset threshold until it persists across several readings, hiding both the rounding flicker and the stale-snapshot rebound; resets (a large jump back toward ~100%) appear immediately, and the recorded history always stays raw.
- Keeps showing the last successful value with its timestamp and failure reason when a provider is temporarily unavailable; stale values are not recorded as new history samples.
- Copies a **diagnostic summary** containing only version, operating-system version, connection state, window kinds, and safe error codes. It excludes raw CLI output, file paths, user names, and credentials.
- Can start automatically when you log in (optional).
- Selects Turkish or English from the operating-system language on first launch and remembers the user's selection.
- Refreshes usage on a selectable interval (1, 2, or 5 minutes; 5 by default) and when the panel opens with data older than 30 seconds.

#### Platform notes

Both platforms share the same rules, but implement them differently.

**macOS**

- Runs only in the menu bar, without a Dock icon or main window.
- Automatic start uses the macOS **Login Items** system.
- Reads the ChatGPT app or an installed Codex CLI for Codex, and an installed Claude Code CLI for Claude.
- Provider commands run in a separate process group.

**Windows**

- A native **C# / .NET 8 / WPF** system-tray application; it creates no taskbar button and no main window.
- Codex's official Windows installation is supported.
- Claude Code's native Windows installation is supported.
- Reading Claude Code through **WSL** is supported, but was not physically validated for the 1.9.0 release.
- Distributed as a **portable ZIP** and a **per-user installer**.
- The installer does not require administrator permission.
- The installer **deliberately does not start UsageBar automatically**; after installation the app is opened from the Start Menu.
- The autostart preference belongs to UsageBar and is stored only in the current user's settings.
- Provider processes are started with `CreateProcessW` and contained in a **Job Object**; their output is bounded.
- There is no shell fallback, service, driver, scheduled task, or `PATH` modification.

### How is the percentage calculated?

The displayed value is the **remaining percentage, not the used percentage**.

- **Claude Code:** Always shows the five-hour window when it is available, falling back to weekly usage only when five-hour data is missing.
- **Codex:** Shows the lowest remaining percentage among the windows available on the account. If the account exposes only a weekly window, UsageBar uses that window.

Click the icon to see every window returned by the selected provider.

### Requirements

You only need to install the provider you want to track.

#### macOS

- macOS 13 or later
- Apple Silicon (`arm64`)
- The ChatGPT app or a signed-in Codex CLI installation for Codex tracking
- A signed-in Claude Code CLI installation for Claude tracking
- Xcode Command Line Tools only when building from source

#### Windows

- Windows 10 version 1809 or later, including Windows 11
- An x64 processor and operating system
- A signed-in official Windows Codex installation for Codex tracking
- A signed-in native Claude Code installation for Claude tracking
- WSL Claude support exists but was not physically validated for the 1.9.0 release
- End users do not need to install the .NET Runtime separately; the package is self-contained
- The .NET 8 SDK only when building from source

### Download and install — macOS

1. Download `macOS-arm64.zip` from the [v1.9.0](https://github.com/akwnnwastaken/UsageBar/releases/tag/v1.9.0) release.
2. Extract the ZIP and move `UsageBar.app` to the **Applications** folder.
3. Open UsageBar and connect a provider from the `%—` icon in the menu bar.

> [!WARNING]
> This package supports Apple Silicon (`arm64`) Macs and has not yet been notarized by Apple. macOS may therefore report that Apple could not verify UsageBar is free of malware. Follow the steps below only if you downloaded the official Release file from this repository.

#### Approving the macOS warning on first launch

1. Extract the downloaded ZIP and move `UsageBar.app` to the **Applications** folder.
2. Try to open UsageBar once.
3. When the verification warning appears, click **Done** instead of **Move to Bin**.
4. Open Apple menu  → **System Settings** → **Privacy & Security**.
5. Scroll to the **Security** section and find the message stating that UsageBar was blocked.
6. Click **Open Anyway**.
7. Authenticate with Touch ID or your Mac login password, then click **Open** in the confirmation dialog.

This approval is required only on the first launch of the same app. If **Open Anyway** is missing, try to open UsageBar again and return to Privacy & Security. Apple makes this option available for about one hour after the launch attempt.

> [!CAUTION]
> Do not disable Gatekeeper globally or run arbitrary `sudo`, `spctl`, or `xattr` commands from the internet. If macOS reports that the app contains known malware, do not continue; delete the file and download it again from the official Release.

#### Verifying the macOS download

To compare the downloaded file's SHA-256 value with the value published on the Release page:

```sh
shasum -a 256 ~/Downloads/UsageBar-1.9.0-macOS-arm64.zip
```

For CI-produced packages, you can also verify GitHub build provenance:

```sh
gh attestation verify ~/Downloads/UsageBar-1.9.0-macOS-arm64.zip \
  --repo akwnnwastaken/UsageBar \
  --signer-workflow akwnnwastaken/UsageBar/.github/workflows/release-candidate.yml
```

SHA-256 verifies that the file did not change; the attestation verifies that it was produced by this repository's pinned GitHub Actions workflow. Checking both provides the strongest free verification available for the current release.

Apple's official instructions: [Open an app Apple cannot check for malicious software](https://support.apple.com/guide/mac-help/mchleab3a043/mac)

### Download and install — Windows

#### Installer — recommended

1. Open the [windows-v1.9.0](https://github.com/akwnnwastaken/UsageBar/releases/tag/windows-v1.9.0) release.
2. Download `UsageBar-Setup-x64.exe`.
3. Optionally verify it against the `.sha256` file beside it (see below).
4. Run the installer. It does not ask for administrator permission and installs for the current user only.
5. **The installer does not launch UsageBar automatically.** This is deliberate.
6. Open the Start menu, type `UsageBar`, and select the app.
7. UsageBar runs in the system tray.
8. If the icon is hidden, check the `^` overflow area on the taskbar.

> [!WARNING]
> This installer is currently unsigned. Windows SmartScreen may show a warning. Compare the file's SHA-256 value with the value on the Release page before continuing. Do not disable SmartScreen globally.

#### Portable

1. Download `UsageBar-Windows-x64.zip`.
2. Extract it to a permanent, writable folder.
3. Do not run the application directly from inside the ZIP.
4. Run `UsageBar.exe`.

#### Verifying the Windows download

In PowerShell, from the folder containing the downloaded file:

```powershell
Get-FileHash .\UsageBar-Setup-x64.exe -Algorithm SHA256
Get-FileHash .\UsageBar-Windows-x64.zip -Algorithm SHA256
```

Compare the result with the matching `.sha256` file on the same Release page and with the value in the Release notes. All three should be identical.

### Usage

1. Open UsageBar. On Windows, if you used the installer, open the app from the Start menu the first time.
2. Click the `%—` icon in the macOS menu bar or the Windows system tray.
3. Choose **Connect Codex** or **Connect Claude Code**.
4. If both providers are connected, use `Auto | Codex | Claude` to pin one provider or enable 30-second automatic rotation.
5. Customize the display and refresh frequency through the appearance, usage colors, usage history, and refresh interval settings.
6. When reporting a problem, use **Copy diagnostics** to obtain a summary without personal data.

Connecting a provider only saves a local preference. UsageBar does not store passwords, API keys, access tokens, or session tokens.

When the mini chart is enabled, UsageBar stores only the measurement time and remaining percentage for each provider/window pair, locally. The chart initially shows only the span actually recorded and grows toward 24 hours. Data is pruned on launch and after every measurement using 24-hour, series-count, and sample-count limits; provider responses, command output, and credentials are never written to history.

### Privacy and permissions

UsageBar does not access either provider on first launch. It queries a provider only after you explicitly click its connection button.

Provider commands run in an app-specific temporary directory with a small environment. Project settings, plugins, MCP servers, Chrome integration, and shell startup files are not loaded. Timeouts terminate every child process and output is limited to 2 MiB. Provider executables are validated before use.

#### macOS

The app does not require:

- Full Disk Access
- Documents or Desktop access
- Network volume access
- Screen Recording
- Accessibility
- Automation

When connecting Claude Code, macOS may request access to the existing `Claude Code-credentials` Keychain item. Choose **Always Allow** once if you do not want the prompt to reappear. Other unrelated permission requests can be denied.

The **Launch at login** option uses only the macOS Login Items system and should be enabled while the app is in `/Applications`. macOS may show a system notification or require approval in System Settings; no screen, disk, or automation permission is granted.

Provider commands run in a separate process group; resolved symlink targets, ownership, and write permissions of provider executables are validated before use.

#### Windows

- The installer does not require administrator permission.
- No service or driver is installed.
- No scheduled task is created.
- `PATH` is not modified.
- There is no telemetry or crash-reporting dependency.
- Provider executables are validated before use.
- Provider processes are contained in a Job Object and their output is bounded.
- UsageBar does not store provider passwords, access tokens, or raw command output as history.

The autostart preference belongs to UsageBar and is stored only in the current user's settings; the installer neither creates nor removes it.

### Data sources

- **Codex:** The installed Codex tool's local `account/rateLimits/read` interface.
- **Claude Code:** the output of Claude Code's local usage command — a local command that leaves no session record and consumes no model quota.

UsageBar does not sign in to provider websites itself. It uses the existing local Codex and Claude Code sessions on your computer.

### Build from source

#### macOS

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

#### Windows

The Windows side is a separate .NET solution and does not use the macOS `build.sh` workflow. Run the commands from the `windows/` folder: the SDK version is pinned to .NET 8 by the `global.json` there.

```powershell
git clone https://github.com/akwnnwastaken/UsageBar.git
cd UsageBar/windows
dotnet restore UsageBar.Windows.sln
dotnet build UsageBar.Windows.sln --configuration Release --no-restore
dotnet test UsageBar.Windows.sln --configuration Release
```

To run the application directly:

```powershell
dotnet run --project src/UsageBar.Windows.App/UsageBar.Windows.App.csproj -c Release
```

To produce the portable package and the installer:

```powershell
./scripts/package.ps1
./scripts/package-installer.ps1
```

`package.ps1` produces the self-contained portable ZIP and `package-installer.ps1` builds the installer with Inno Setup. To run the produced packages through the same gates CI uses:

```powershell
./scripts/verify-package.ps1
./scripts/verify-installer.ps1
```

The `Core` and `Core.Tests` projects target `net8.0` and build and run on any platform; Windows-specific tests are skipped elsewhere. See [`docs/windows-port.md`](docs/windows-port.md) for details.

### Project structure

```text
UsageBar/
├── Sources/UsageBar/main.swift             # macOS application, UI, and provider readers
├── Sources/UsageBarCore/Core.swift         # Pure rules covered by XCTest
├── Sources/UsageBarProcessLauncher/        # Shell-free process-group launcher
├── Package.swift                           # Canonical SwiftPM build graph
├── Info.plist                              # macOS application and version metadata
├── build.sh                                # macOS build, test, and local signing
├── tests/                                  # XCTest suite and macOS acceptance scripts
├── windows/
│   ├── UsageBar.Windows.sln                # Windows solution
│   ├── Directory.Build.props               # Shared version and compiler settings
│   ├── global.json                         # .NET 8 SDK pin
│   ├── src/                                # Core, Infrastructure, and the WPF tray app
│   ├── tests/                              # xUnit suites
│   ├── scripts/                            # Packaging, installer, and verification scripts
│   └── installer/                          # Inno Setup definition and application icon
├── shared/fixtures/                        # Provider sample output shared by both platforms
├── docs/windows-port.md                    # Windows port design and validation notes
├── .github/workflows/ci.yml                # macOS packaging and security checks
├── .github/workflows/windows-ci.yml        # Windows build, test, and packaging gates
├── .github/workflows/release-candidate.yml # Signed tag, SHA, and provenance build
├── SECURITY.md                             # Bilingual vulnerability reporting policy
├── LICENSE                                 # MIT License
└── README.md                               # Turkish and English documentation
```

### Development

Changes are developed through separate commits and pull requests. This keeps each change reviewable and makes it possible to return to earlier working versions through Git history.

Report sensitive vulnerabilities through the private process in the [security policy](SECURITY.md), not a public Issue.

### License

UsageBar is available under the [MIT License](LICENSE).
