# UsageBar

Codex ve Claude Code kullanım limitlerini macOS menü çubuğunda gösteren küçük ve yerel bir uygulama.

UsageBar, seçtiğiniz sağlayıcının **kalan kullanım oranını** simgesiyle birlikte üst çubukta gösterir. Ayrıntı menüsünde kullanım pencerelerini, kalan yüzdeleri ve sıfırlanmaya kalan süreyi görebilirsiniz.

## Özellikler

- Codex ve Claude Code kullanımını tek uygulamada izler.
- Menü çubuğunda seçili sağlayıcının en düşük kalan oranını gösterir.
- 5 saatlik ve haftalık pencereleri ayrı ayrı listeler; yalnızca hesapta bulunan pencereleri gösterir.
- Sıfırlama zamanını yüzde bilgisinin altında gösterir (`1sa 15dk` / `1h 15m`).
- Kalan oranı seviyesine göre yeşil, turuncu veya kırmızı renklendirir.
- Üst çubukta gösterilecek sağlayıcıyı `Codex | Claude` anahtarıyla değiştirir.
- Türkçe ve İngilizce arayüz sunar; seçimleri sonraki açılışlar için saklar.
- Her 5 dakikada bir ve menü yeniden açıldığında kullanım verisini yeniler.
- Dock simgesi veya ana pencere açmadan yalnızca menü çubuğunda çalışır.

## Yüzde nasıl hesaplanıyor?

Üst çubuktaki değer **kullanılan değil, kalan yüzdedir**.

Örneğin seçili sağlayıcının 5 saatlik penceresinde `%35`, haftalık penceresinde `%20` kullanım hakkı kaldıysa üst çubukta daha kritik olan `%20` gösterilir. Menüye tıkladığınızda iki pencerenin ayrıntısını da görebilirsiniz.

## Gereksinimler

- macOS 13 veya daha yeni bir sürüm
- Codex için ChatGPT uygulaması veya giriş yapılmış Codex CLI
- Claude için giriş yapılmış Claude Code CLI
- Kaynak koddan derlemek için Xcode Command Line Tools

Yalnızca kullanmak istediğiniz sağlayıcının kurulu olması yeterlidir.

## İndir ve kur

1. [Releases](https://github.com/akwnnwastaken/UsageBar/releases) sayfasından en güncel `macOS-arm64.zip` dosyasını indirin.
2. ZIP dosyasını açın ve `UsageBar.app` uygulamasını **Applications** klasörüne taşıyın.
3. UsageBar'ı açın; menü çubuğundaki `%—` simgesinden sağlayıcınızı bağlayın.

> [!WARNING]
> İlk Beta sürümü Apple Silicon (`arm64`) Mac'ler içindir ve henüz Apple tarafından notarize edilmemiştir. Bu nedenle macOS ilk açılışta “Apple, UsageBar öğesinin Mac'inize zarar verecek kötü amaçlı yazılım içermediğini doğrulayamadı” uyarısını gösterebilir. Aşağıdaki adımlar yalnızca bu depodaki resmi Release dosyasını indirdiyseniz uygulanmalıdır.

### İlk açılışta macOS uyarısını onaylama

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
shasum -a 256 ~/Downloads/UsageBar-1.4.2-macOS-arm64.zip
```

Apple'ın resmi açıklaması: [Apple'ın kötü amaçlı yazılım denetimi yapamadığı bir uygulamayı açma](https://support.apple.com/guide/mac-help/mchleab3a043/mac)

## Kullanım

1. UsageBar'ı açın.
2. Menü çubuğundaki `%—` simgesine tıklayın.
3. **Codex'e bağlan** veya **Claude Code'a bağlan** seçeneğini kullanın.
4. İki sağlayıcı da bağlıysa üst çubukta gösterilecek olanı `Codex | Claude` anahtarıyla seçin.

Bağlantı seçimi yalnızca yerel tercihi kaydeder. UsageBar şifre, erişim anahtarı veya oturum belirteci saklamaz.

## Gizlilik ve macOS izinleri

UsageBar ilk açılışta hiçbir sağlayıcıya erişmez. Bir sağlayıcıyı ancak ilgili bağlantı düğmesine bastığınızda sorgular.

Uygulama şunlara ihtiyaç duymaz:

- Tam Disk Erişimi
- Belgeler veya Masaüstü erişimi
- Ağ diski erişimi
- Ekran Kaydı
- Erişilebilirlik
- Otomasyon

Claude Code bağlantısında macOS, mevcut `Claude Code-credentials` Anahtar Zinciri kaydı için izin isteyebilir. Sürekli sorulmaması için bu pencerede bir kez **Her Zaman İzin Ver** seçilebilir. Bunun dışındaki izin istekleri reddedilebilir.

Sağlayıcı komutları uygulamaya özel geçici bir klasörde çalıştırılır. Proje ayarları, eklentiler, MCP sunucuları, Chrome entegrasyonu ve kabuk başlangıç ayarları yüklenmez.

## Veri kaynakları

- **Codex:** Kurulu Codex aracının `account/rateLimits/read` yerel arayüzü.
- **Claude Code:** Claude Code'un resmi `rate_limits.five_hour` ve `rate_limits.seven_day` alanları; gerektiğinde `/usage` çıktısı yedek olarak kullanılır.

UsageBar sağlayıcıların web sitelerine kendi hesabıyla giriş yapmaz; bilgisayarınızdaki mevcut Codex ve Claude Code oturumlarını kullanır.

## Kaynak koddan derleme

```sh
git clone https://github.com/akwnnwastaken/UsageBar.git
cd UsageBar
chmod +x build.sh
./build.sh
open build/UsageBar.app
```

Derleme betiği uygulamayı oluşturur, yerleşik parser ve yerelleştirme testlerini çalıştırır ve yerel kullanım için ad hoc imzalar.

## Proje yapısı

```text
UsageBar/
├── Sources/UsageBar/main.swift   # Uygulama, arayüz ve veri okuyucuları
├── Info.plist                    # macOS uygulama ayarları
├── build.sh                      # Derleme, test ve yerel imzalama
├── LICENSE                       # MIT Lisansı
└── README.md
```

## Geliştirme

Değişiklikler ayrı commitler ve taslak pull request üzerinden ilerletilir. Böylece GitHub'daki commit geçmişinden önceki çalışan sürümlere dönülebilir ve her değişiklik ayrı ayrı incelenebilir.

## Lisans

UsageBar, [MIT Lisansı](LICENSE) ile sunulur.
