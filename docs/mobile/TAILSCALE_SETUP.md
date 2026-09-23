# Tailscale setup / Tailscale kurulumu

[English](#english) · [Türkçe](#türkçe)

UsageBar Mobile has no server. Your iPhone reaches your Mac directly, over your
own private Tailscale network, and Tailscale is the only reason that works from
outside your home Wi-Fi.

Tailscale is the **connectivity layer, not a backend**: your usage data never
rests on anyone's infrastructure, including Tailscale's.

Everything below is done once. UsageBar never configures Tailscale for you — it
only reads your connection status, and it cannot change a setting even if it
wanted to.

---

<a id="english"></a>

## English

### The shape of it

```
    UsageBar (Mobile Sync)  ──►  127.0.0.1:18642    (loopback, never the network)
                                     ▲
                                     │  Tailscale Serve terminates HTTPS
                                     │  and injects your Tailscale identity
                                     │
    iPhone  ──── HTTPS over your tailnet ────────────┘
```

The Mac service listens on loopback and **nothing else**. Tailscale Serve is the
only way in. That is a security property, not a preference: Serve's injected
identity header is only trustworthy while Serve is the sole path to the service.

### 1. Install Tailscale on both devices

[tailscale.com/download](https://tailscale.com/download). Sign both the Mac and
the iPhone into the **same tailnet** — the same account, or the same shared
network.

Check on the Mac:

```sh
tailscale status
```

The iPhone should be listed. If Tailscale is installed from the Mac App Store,
the CLI lives inside the app bundle:

```sh
/Applications/Tailscale.app/Contents/MacOS/Tailscale status
```

Add an alias for it if you will use it more than once.

### 2. Name the Mac before you enable certificates — this one matters

Tailscale issues its HTTPS certificates through the public **Certificate
Transparency** logs. Those logs are permanent and public, so your Mac's
MagicDNS name and your tailnet name become publicly searchable the moment a
certificate is issued.

Machine names are frequently taken from the owner's own name. Before enabling
certificates, rename the Mac to something generic in the
[Machines page](https://login.tailscale.com/admin/machines) of the admin
console:

| Instead of | Prefer |
| --- | --- |
| `ahmets-macbook-pro` | `desk`, `studio`, `workstation` |

Rename **first**. A certificate already issued cannot be unpublished.

### 3. Enable HTTPS Certificates for the tailnet

Admin console ▸ **DNS** ▸ **HTTPS Certificates** ▸ Enable. This is a
tailnet-wide setting and only an owner or admin can change it.

Your Mac's HTTPS name is then:

```
<machine-name>.<your-tailnet>.ts.net
```

for example `desk.example-tail.ts.net`. That full name is what you will see in
the pairing QR, and it is the only address the iPhone app accepts — it rejects
raw `100.x` addresses, ports, paths and URLs outright.

### 4. Point Serve at the UsageBar service

On the Mac, with UsageBar running and Mobile Sync enabled:

```sh
tailscale serve --bg 18642
```

That publishes `https://<machine>.<tailnet>.ts.net/` to the local service on
`127.0.0.1:18642`, in the background, for your tailnet only.

Check it:

```sh
tailscale serve status
```

You should see your HTTPS name mapped to `http://127.0.0.1:18642`. Before you
configure anything, the same command prints `No serve config`.

Remove it when you are done:

```sh
tailscale serve reset
```

> **Never use `tailscale funnel`.** Funnel publishes a service to the **public
> internet**. UsageBar Mobile is designed for a private tailnet and must never
> be exposed that way. Serve is tailnet-only; Funnel is not.

### 5. Check the phone can see the Mac

On the iPhone, open the Tailscale app and confirm it is connected and the Mac is
listed. Then pair: [first run and pairing](SELF_BUILD.md#5-connect-tailscale-then-pair).

### What UsageBar does and does not do with Tailscale

| | |
| --- | --- |
| Reads your Tailscale status, read-only | yes |
| Configures Serve, Funnel or DNS | **no** |
| Creates or edits grants, ACLs, tags, auth keys or OAuth clients | **no** |
| Contains a Tailscale SDK, `tsnet`, a VPN profile or a NetworkExtension | **no** |
| Sends a Tailscale identity header from the app | **no** — Serve injects it |
| Puts your hostname, tailnet or address into the synced data | **no** |

The phone app speaks ordinary HTTPS. Your Tailscale client supplies the
reachability, and nothing else.

### Least privilege

Being on the same tailnet is **not** authorization to read your usage. Every
request must also carry a credential that was issued to one specific Tailscale
identity during pairing, and both are checked. A tighter Tailscale grant is
designed in [`mobile-transport-grants-plan.md`](mobile-transport-grants-plan.md)
and is deliberately **not applied** by anything in this release — grants stay
yours to write.

### If something does not connect

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

---

<a id="türkçe"></a>

## Türkçe

### İşin şekli

```
    UsageBar (Mobil Eşitleme)  ──►  127.0.0.1:18642 (yalnızca loopback, ağ değil)
                                     ▲
                                     │  Tailscale Serve HTTPS'i sonlandırır
                                     │  ve Tailscale kimliğini ekler
                                     │
    iPhone  ──── tailnet üzerinden HTTPS ────────────┘
```

Mac'teki servis yalnızca loopback'i dinler, **başka hiçbir arayüzü değil**. Tek
giriş yolu Tailscale Serve'dür. Bu bir tercih değil, bir güvenlik özelliğidir:
Serve'ün eklediği kimlik başlığı, yalnızca Serve tek yol olduğu sürece
güvenilirdir.

### 1. Tailscale'i iki cihaza da kur

[tailscale.com/download](https://tailscale.com/download). Mac'i de iPhone'u da
**aynı tailnet**'e bağla — aynı hesap ya da paylaşılan aynı ağ.

Mac'te kontrol et:

```sh
tailscale status
```

iPhone listede görünmeli. Tailscale'i Mac App Store'dan kurduysan CLI uygulama
paketinin içindedir:

```sh
/Applications/Tailscale.app/Contents/MacOS/Tailscale status
```

Birden fazla kez kullanacaksan bir alias tanımla.

### 2. Sertifikayı açmadan önce Mac'e ad ver — bu madde önemli

Tailscale, HTTPS sertifikalarını herkese açık **Certificate Transparency**
kayıtları üzerinden verir. Bu kayıtlar kalıcıdır ve herkese açıktır; yani
sertifika verildiği anda Mac'inin MagicDNS adı ve tailnet adın herkesin
arayabileceği bir kayda girer.

Makine adları çoğu zaman sahibinin adından türer. Sertifikaları açmadan önce
yönetim konsolunun
[Machines sayfasından](https://login.tailscale.com/admin/machines) Mac'e genel
bir ad ver:

| Yerine | Tercih et |
| --- | --- |
| `ahmets-macbook-pro` | `desk`, `studio`, `workstation` |

**Önce** adı değiştir. Verilmiş bir sertifika geri çekilemez.

### 3. Tailnet için HTTPS Sertifikalarını aç

Yönetim konsolu ▸ **DNS** ▸ **HTTPS Certificates** ▸ Enable. Bu tailnet
genelinde bir ayardır ve yalnızca sahip veya yönetici değiştirebilir.

Mac'inin HTTPS adı şu olur:

```
<makine-adı>.<tailnet-adın>.ts.net
```

örneğin `desk.example-tail.ts.net`. Eşleştirme QR'ında göreceğin ad budur ve
iPhone uygulamasının kabul ettiği tek adres biçimidir — çıplak `100.x`
adreslerini, portları, yolları ve URL'leri doğrudan reddeder.

### 4. Serve'ü UsageBar servisine yönlendir

Mac'te, UsageBar çalışırken ve Mobil Eşitleme açıkken:

```sh
tailscale serve --bg 18642
```

Bu, `https://<makine>.<tailnet>.ts.net/` adresini arka planda ve yalnızca
tailnet'ine açık olacak şekilde `127.0.0.1:18642` üzerindeki yerel servise
bağlar.

Kontrol et:

```sh
tailscale serve status
```

HTTPS adının `http://127.0.0.1:18642` ile eşlendiğini görmelisin. Hiçbir şey
yapılandırmadan önce aynı komut `No serve config` yazar.

İşin bitince kaldır:

```sh
tailscale serve reset
```

> **`tailscale funnel` asla kullanma.** Funnel bir servisi **halka açık
> internete** yayınlar. UsageBar Mobile özel bir tailnet için tasarlanmıştır ve
> bu şekilde açılmamalıdır. Serve yalnızca tailnet'e açıktır; Funnel değildir.

### 5. Telefonun Mac'i gördüğünü doğrula

iPhone'da Tailscale uygulamasını aç; bağlı olduğunu ve Mac'in listelendiğini
doğrula. Sonra eşleştir:
[ilk çalıştırma ve eşleştirme](SELF_BUILD.md#5-tailscalei-bağla-sonra-eşleştir).

### UsageBar Tailscale ile ne yapar, ne yapmaz

| | |
| --- | --- |
| Tailscale durumunu salt-okunur okur | evet |
| Serve, Funnel veya DNS yapılandırır | **hayır** |
| Grant, ACL, tag, auth key veya OAuth istemcisi oluşturur/düzenler | **hayır** |
| Tailscale SDK, `tsnet`, VPN profili veya NetworkExtension içerir | **hayır** |
| Uygulamadan Tailscale kimlik başlığı gönderir | **hayır** — onu Serve ekler |
| Ana bilgisayar adını, tailnet'ini veya adresini eşitlenen veriye koyar | **hayır** |

Telefon uygulaması sıradan HTTPS konuşur. Erişilebilirliği Tailscale istemcin
sağlar, başka hiçbir şey değil.

### En az yetki

Aynı tailnet'te olmak, kullanımını okumak için **yetki değildir**. Her istek
ayrıca, eşleştirme sırasında tek bir Tailscale kimliğine verilmiş bir kimlik
bilgisi taşımak zorundadır ve ikisi birden denetlenir. Daha dar bir Tailscale
grant'ı [`mobile-transport-grants-plan.md`](mobile-transport-grants-plan.md)
içinde tasarlanmıştır ve bu sürümdeki hiçbir şey tarafından bilinçli olarak
**uygulanmaz** — grant'lar senin yazacağın şeydir.

### Bağlanmıyorsa

Bkz. [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
