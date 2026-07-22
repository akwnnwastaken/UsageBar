# UsageBar

Codex ve Claude Code kullanımını macOS menü çubuğunda tek yüzde olarak gösteren küçük, yerel bir uygulama.

- Menü çubuğundaki `%35`, kullanıcının seçtiği servisin kullanım pencereleri içinde **en az kalan oranı** gösterir.
- Yüzdenin yanında seçilen Codex/ChatGPT veya Claude simgesi gösterilir.
- Hesaplar bir kez **Codex'e bağlan** ve **Claude Code'a bağlan** düğmeleriyle eklenir. Bağlandıktan sonra bu düğmeler kaybolur; bağlantı bir takip tikiyle yanlışlıkla kesilemez.
- Üst çubukta gösterilecek servis, menüdeki `Codex | Claude` bölümlü anahtarıyla seçilir.
- Menüdeki `Türkçe | English` anahtarıyla arayüz dili anında değiştirilir ve tercih sonraki açılışlar için saklanır.
- Sıfırlama zamanı yüzde bilgisinin altında ayrı bir satırda gösterilir; İngilizcede iki parçalı ve kısa yazılır: örneğin `1h 15m` veya `6d 21h`.
- Kullanım kartlarında kalan yüzdeler seviyeye göre yeşil, turuncu veya kırmızı vurgulanır; menü gereksiz kısayol kolonu olmadan kompakt çizilir.
- Menü açıldığında Codex ve Claude Code için hesapta gerçekten bulunan pencerelerin kalan yüzdeleri görünür. Haftalık-only Codex hesapları yanlışlıkla 5 saatlik olarak etiketlenmez.
- Her 5 dakikada bir ve menü açıldığında yenilenir.
- Şifre veya erişim anahtarı saklamaz.
- İlk açılışta hiçbir sağlayıcıya erişilmez. Yalnızca kullanıcı ilgili bağlantı düğmesine bastığında yerel Codex veya Claude Code oturumuna erişilir.
- Tam Disk Erişimi, Belgeler/Masaüstü, Ekran Kaydı, Erişilebilirlik veya Otomasyon izni istemez ve bunlara ihtiyaç duymaz.

## Veri kaynakları

- Codex: Kurulu Codex aracının resmi `account/rateLimits/read` yerel arayüzü.
- Claude Code: Kurulu Claude Code aracındaki `/usage` ekranı. Yüzdelerle birlikte 5 saatlik ve haftalık sıfırlama zamanları okunur. Claude Code hesabına giriş yapılmış olmalıdır.

Claude takibini etkinleştirirseniz macOS, `Claude Code-credentials` Anahtar Zinciri kaydı için izin sorabilir. Sürekli sorulmaması için bu pencerede bir kez **Her Zaman İzin Ver** seçilebilir. Bu, Claude yüzdesini okuyabilmek için gereken tek isteğe bağlı izindir.

Claude sorgusu uygulamaya özel geçici bir klasörde, kullanıcı/proje ayar kaynakları kapatılmış izole bir Claude Code oturumunda çalışır. Yalnızca resmi `rate_limits.five_hour` ve `rate_limits.seven_day` alanlarını yazdıran geçici durum satırı eklenir. Proje dosyaları, eklentiler, MCP sunucuları, Chrome entegrasyonu ve kabuk başlangıç ayarları yüklenmez. Ağ diski, Belgeler, Masaüstü, ekran kaydı, erişilebilirlik veya otomasyon izni gerekmez; bu izinlerden biri görülürse reddedilebilir.

## Derleme

```sh
chmod +x build.sh
./build.sh
open build/UsageBar.app
```

Uygulama Dock'ta görünmez. Menü çubuğundaki yüzdeye tıklayarak ayrıntıları açabilirsiniz.
