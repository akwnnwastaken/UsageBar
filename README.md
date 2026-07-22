# UsageBar

Codex ve Claude Code kullanımını macOS menü çubuğunda tek yüzde olarak gösteren küçük, yerel bir uygulama.

- Menü çubuğundaki `%35`, iki servisin 5 saatlik pencereleri içindeki **en yüksek kullanılan oranı** gösterir.
- Menü açıldığında Codex ve Claude Code için 5 saatlik ve haftalık oranlar ayrı görünür.
- Her 5 dakikada bir ve menü açıldığında yenilenir.
- Şifre veya erişim anahtarı saklamaz.
- Codex takibi ilk açılışta açıktır. Claude Code takibi varsayılan olarak kapalıdır ve yalnızca menüden açıkça etkinleştirildiğinde Claude kimliğine erişir.
- Tam Disk Erişimi, Belgeler/Masaüstü, Ekran Kaydı, Erişilebilirlik veya Otomasyon izni istemez ve bunlara ihtiyaç duymaz.

## Veri kaynakları

- Codex: Kurulu Codex aracının resmi `account/rateLimits/read` yerel arayüzü.
- Claude Code: Kurulu Claude Code aracındaki `/usage` ekranı. Claude Code hesabına giriş yapılmış olmalıdır.

Claude takibini etkinleştirirseniz macOS, `Claude Code-credentials` Anahtar Zinciri kaydı için izin sorabilir. Bu, Claude yüzdesini okuyabilmek için gereken tek isteğe bağlı izindir.

## Derleme

```sh
chmod +x build.sh
./build.sh
open build/UsageBar.app
```

Uygulama Dock'ta görünmez. Menü çubuğundaki yüzdeye tıklayarak ayrıntıları açabilirsiniz.
