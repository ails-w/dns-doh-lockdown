# Módulo 01 — DNS y systemd-resolved

Cómo el sistema convierte nombres en IPs, y cómo se le añaden **filtrado** y **cifrado**.
Es la capa que decide *qué* se resuelve; el módulo 02 se encarga de que *nadie* pueda
preguntar por otro camino.

> Implementación → [`modules/01-resolved-dns/`](../../modules/01-resolved-dns/README.md)

## Glosario del módulo

| Término | Qué significa (en una línea) |
|---|---|
| `getaddrinfo` | La función de C que usan casi todas las apps para resolver nombres. |
| NSS | *Name Service Switch*: la capa de glibc que decide *por dónde* resolver. |
| `/etc/nsswitch.conf` | El archivo que configura NSS. |
| stub resolver | Resolver local de `systemd-resolved` escuchando en `127.0.0.53`. |
| `/etc/resolv.conf` | Archivo clásico con los servidores DNS; suele ser un symlink al stub. |
| DoT | *DNS over TLS*: DNS cifrado en el puerto `853`. |
| SNI | El nombre que el cliente declara en el handshake TLS; se usa para validar el certificado. |
| fallback | Servidor alternativo si el principal falla. |
| `ReadEtcHosts` | Opción de `resolved` que le dice que lea `/etc/hosts`. |

## Mapa de conceptos

```text
  app ──▶ getaddrinfo ──▶ NSS (/etc/nsswitch.conf)
                              │
                              ├─ "files"  → /etc/hosts
                              └─ "resolve"→ 127.0.0.53 (stub)
                                              │
                                              ▼
                                        systemd-resolved
                                              │
                                              ├─ /etc/hosts   (ReadEtcHosts)
                                              └─ upstream: 1.1.1.3 vía DoT
```

---

## 1. `getaddrinfo` y NSS

### En una frase

Las apps no "saben" de DNS: le piden un nombre a glibc, y glibc decide por dónde buscarlo
según `/etc/nsswitch.conf`.

### Fundamentos previos

- DNS (ver [`00-fundamentos.md`](00-fundamentos.md)).

### Qué es

`getaddrinfo()` es la llamada estándar para traducir nombre → dirección. No resuelve ella
misma: consulta la capa **NSS**, que ejecuta en orden los "backends" listados en
`/etc/nsswitch.conf` para la base de datos `hosts`.

### Qué problema resuelve

Desacopla *quién pregunta* de *cómo se responde*. Podrías pasar de archivos locales a DNS,
a LDAP, a mDNS, sin tocar las apps.

### Cómo funciona paso a paso

1. La app llama a `getaddrinfo("example.com", ...)`.
2. NSS lee la línea `hosts:` de `/etc/nsswitch.conf`.
3. Ejecuta los backends en orden. En este proyecto: `files` (para `/etc/hosts`) y
   `resolve` (para `systemd-resolved`).
4. El primero que responde, gana.

### Qué se rompería sin esto

Las apps tendrían que implementar su propio resolver: cada navegador, cada herramienta.
Es exactamente lo que hacen algunas apps — y por eso son las que se escapan del filtro.

### Para qué sirve aquí

El proyecto se apoya en que **casi todo** pasa por NSS → `resolved`. Es el punto que se
puede controlar. Lo que no pasa por ahí (apps con resolver propio) es lo que cubren los
módulos 02–04.

### Cómo se usa (archivos reales)

```bash
grep '^hosts:' /etc/nsswitch.conf
# hosts: mymachines resolve [!UNAVAIL=return] files myhostname dns
```

El orden importa: `resolve` va antes que `files`, así que `systemd-resolved` maneja primero.

### Error común

**Editar `/etc/resolv.conf` a mano y creer que eso cambia el DNS de todo.** Muchos equipos
tienen `resolved` o NetworkManager gestionándolo: tu edición se sobrescribe en el próximo
reinicio de red. Además, apps que usan NSS pueden ignorarlo por completo si `nsswitch.conf`
resuelve antes por otro backend.

### Para profundizar

- `man 5 nsswitch.conf`, `man 3 getaddrinfo`.

---

## 2. `systemd-resolved` y el stub

### En una frase

`systemd-resolved` es el resolver del sistema: recibe todo en `127.0.0.53` y decide cómo
resolver (caché, upstream, cifrado, filtrado).

### Fundamentos previos

- `getaddrinfo` y NSS (1).

### Qué es

Un servicio que implementa un resolver local (**stub**) escuchando en `127.0.0.53`, más una
caché y una lógica de "a quién preguntar". `/etc/resolv.conf` normalmente es un **symlink**
a `/run/systemd/resolve/stub-resolv.conf`, así que apunta al stub.

### Qué problema resuelve

Antes cada app y cada conexión tenían su propia idea del DNS. `resolved` centraliza:
un solo lugar para configurar servidores, cifrado, caché y *split DNS* (por interfaz o
dominio).

### Cómo funciona paso a paso

1. La app (vía NSS) pregunta a `127.0.0.53`.
2. `resolved` mira primero sus datos locales (`/etc/hosts`, si `ReadEtcHosts=yes`).
3. Si no está, consulta su upstream configurado (`DNS=`), cachea la respuesta y la devuelve.
4. Si configuraste DoT, esa consulta al upstream va cifrada.

### Qué se rompería sin esto

Volverías al caos de resolv.conf: sin caché, sin cifrado, sin un punto único que el firewall
pueda forzar.

### Para qué sirve aquí

Es la capa 1 completa: filtrado + cifrado + caché + punto único. Todo lo demás se apoya en
que este punto existe y es controlable.

### Cómo se usa (archivos reales)

Drop-in del módulo 01:

```ini
[Resolve]
DNS=1.1.1.3#cloudflare-dns.com 1.0.0.3#cloudflare-dns.com
FallbackDNS=
Domains=~.
DNSOverTLS=opportunistic
DNSSEC=allow-downgrade
Cache=yes
```

Verificar:

```bash
resolvectl status
resolvectl query example.com
```

### Error común

**Dejar `FallbackDNS` con valores por defecto.** Si el resolver filtrado falla, el sistema
puede resolver por un servidor **sin filtro** sin que te enteres. En este proyecto va vacío
a propósito: si el filtro no está, no se resuelve.

### Para profundizar

- `man 5 resolved.conf`, `man 1 resolvectl`.

---

## 3. DoT (DNS over TLS)

### En una frase

Cifra las consultas DNS en un canal TLS dedicado (puerto `853`) para que nadie en la red
las lea ni las modifique.

### Fundamentos previos

- DNS (1), `resolved` (2).
- TLS: el mismo cifrado de HTTPS, pero aplicado al protocolo DNS.

### Qué es

Un canal TLS estándar (como HTTPS) donde el cliente y el resolver intercambian consultas
DNS. A diferencia de DoH, usa su **propio puerto** (`853`), lo que lo hace *visible* para un
firewall: se puede permitir o bloquear fácilmente.

### Qué problema resuelve

DNS en claro es espiable y modificable. DoT lo evita sin mezclar DNS con HTTPS.

### Cómo funciona paso a paso

1. El cliente abre TLS a la IP del resolver en `853`.
2. En el handshake declara el nombre (`SNI`) para validar el certificado.
3. Sobre ese canal, intercambia consultas y respuestas DNS.

El sufijo `#cloudflare-dns.com` en `DNS=` es precisamente ese nombre de validación: **no**
se resuelve por DNS, solo se usa para comprobar el certificado.

### Qué se rompería sin esto

Tus consultas viajarían en claro: quien esté en la red podría verlas y hasta redirigirlas.

### Para qué sirve aquí

Es el "cifrado" de la capa 1. El módulo 02 lo restringe a `1.1.1.3`/`1.0.0.3`: si una app
intenta DoT contra otro servidor, se corta.

### Cómo se usa (archivos reales)

```bash
# El firewall solo permite DoT hacia Families (módulo 02)
ip daddr $CFF4 tcp dport 853 accept
meta l4proto { tcp, udp } th dport 853 drop
```

### Error común

**Elegir `DNSOverTLS=yes` en redes que bloquean `853`.** El resolver quedaría sin poder
resolver nada. `opportunistic` intenta cifrar y, si no puede, cae a DNS en claro **que el
firewall igual redirige al resolver filtrado** — por eso no es una fuga.

### Para profundizar

- `man 5 resolved.conf` (`DNSOverTLS`), RFC 7858.

---

## 4. Cloudflare for Families y el "sin fallback"

### En una frase

El resolver elegido filtra malware y contenido adulto, y el sistema se configura para que
**no exista** una vía alternativa si el filtro no está.

### Fundamentos previos

- Filtrado DNS (ver [`00-fundamentos.md`](00-fundamentos.md), concepto 2).

### Qué es

Cloudflare for Families ofrece dos variantes: `1.1.1.2` (malware) y `1.1.1.3` (malware +
contenido adulto). A un dominio filtrado responde `0.0.0.0`. El proyecto usa `1.1.1.3`.

### Qué problema resuelve

Da filtrado de categorías a nivel de equipo, sin instalar nada por app ni mantener listas.

### Cómo funciona paso a paso

1. El sistema resuelve contra `1.1.1.3` (y `1.0.0.3`) por DoT.
2. Cloudflare clasifica el dominio.
3. Si está filtrado, responde `0.0.0.0` en vez de la IP real.
4. La app no puede conectarse.

### Qué se rompería sin esto

Sin filtrado, el proyecto seguiría bloqueando DoH, pero perdería su objetivo principal:
que el DNS sirva para filtrar contenido.

### Para qué sirve aquí

Es el "qué" de la capa 1. Si prefieres otro resolver, cambia `DNS=` **y** la IP del
firewall (`CFF4` en el módulo 02) para que apunten al mismo sitio.

### Cómo se usa (archivos reales)

```bash
resolvectl query nudity.testcategory.com
# -> bloqueado (Cloudflare responde 0.0.0.0; como no está firmado,
#    resolvectl lo reporta como Filtered/Censored)
```

### Error común

**Pensar que el filtro es una barrera.** Es cooperativo: se salta con DoH, con un resolver
propio o con una app que no use NSS. Por eso existen las capas 2–5.

### Para profundizar

- Documentación de Cloudflare for Families.

---

## 5. `ReadEtcHosts`: el puente con el sinkhole

### En una frase

Una línea que hace que `resolved` consulte `/etc/hosts` antes de ir a la red; sin ella, el
módulo 03 no funcionaría.

### Fundamentos previos

- `resolved` (2).

### Qué es

`ReadEtcHosts=yes` (default en la mayoría de versiones) permite que `resolved` responda
nombres definidos en `/etc/hosts` localmente, sin preguntar al upstream.

### Qué problema resuelve

Da una forma **local y soberana** de sobrescribir la resolución de nombres concretos. Es
exactamente lo que necesita un *sinkhole*: que ciertos nombres nunca lleguen a la red.

### Cómo funciona paso a paso

1. Llega una consulta al stub.
2. `resolved` busca el nombre en `/etc/hosts`.
3. Si está, responde desde ahí ("Data from: synthetic" en `resolvectl`).
4. Si no, consulta al upstream.

### Qué se rompería sin esto

El módulo 03 (sinkhole DoH) sería inútil: `resolved` ignoraría `/etc/hosts` y resolvería los
nombres DoH por la red, devolviendo las IPs reales de los endpoints.

### Para qué sirve aquí

Es la bisagra entre la capa del resolver (01) y la del sinkhole (03). Por eso se deja
explícito en un drop-in propio: para que no dependa del default de la distro.

### Cómo se usa (archivos reales)

```ini
# /etc/systemd/resolved.conf.d/10-read-etc-hosts.conf
[Resolve]
ReadEtcHosts=yes
```

### Error común

**Bloquear nombres en `/etc/hosts` esperando que funcionen con `nsswitch` en orden
`resolve` antes que `files`.** Con `resolve` primero, glibc consulta a `resolved`; si
`resolved` no lee `/etc/hosts` (`ReadEtcHosts=no`), tu bloqueo no se aplica. El síntoma es
`resolvectl query` devolviendo la IP real en lugar de `127.0.0.1`.

### Para profundizar

- `man 5 resolved.conf` (`ReadEtcHosts`), `man 5 hosts`.
- Siguiente: [`02-firewall-nftables.md`](02-firewall-nftables.md).

---

## Relación entre estos conceptos

```text
getaddrinfo/NSS (1)  →  elige el camino
        │
        ▼
systemd-resolved (2) →  el punto único
        │
        ├─ DoT (3)          →  cifra hacia el upstream
        ├─ Families (4)     →  filtra qué se resuelve
        └─ ReadEtcHosts (5) →  permite el sinkhole del módulo 03
```

El orden importa: sin (1) no hay camino controlable; sin (2) no hay punto único; (3) y (4)
son las propiedades que se le dan a ese punto; (5) es la puerta que usará el módulo
siguiente.
