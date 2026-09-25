# Instalación

## Prerrequisitos

| Requisito | Para qué | Nota |
|---|---|---|
| Linux con **systemd** | timers, tmpfiles, resolved | probado en Arch Linux; cualquier distro con systemd sirve |
| `nftables` | módulo 02 | el paquete y el servicio |
| `systemd-resolved` | módulo 01 | con `/etc/resolv.conf` apuntando al stub |
| `sudo` | todos los módulos escriben en `/etc` | — |
| Chromium/Firefox | solo módulo 04 | cualquiera de la familia Chromium + Firefox |
| Docker / libvirt | opcional | el módulo 02 ya contempla sus bridges |

> Los comandos están en **bash** (estándar). Cópialos tal cual.

## Orden recomendado

```text
01-resolved-dns  →  02-firewall-nftables  →  03-doh-sinkhole  →  04-browser-policies  →  05-netguard
```

El orden importa: el firewall (02) asume que ya existe un resolver al que forzar el DNS,
y `netguard` (05) va al final porque **congela** el estado ya correcto de todo lo demás.

Cada módulo es autocontenido: puedes instalar solo el 01, o solo el 02, etc. Los enlaces
a la guía completa de cada uno están en su carpeta.

## Resumen por módulo

### 01 — Resolved DNS (`modules/01-resolved-dns/`)

Deja el resolver del sistema filtrado y cifrado:

- `00-cloudflare-family.conf` → Cloudflare for Families + DoT, sin fallback.
- `10-read-etc-hosts.conf` → fuerza la lectura de `/etc/hosts` (lo necesita el módulo 03).

```bash
sudo cp modules/01-resolved-dns/files/*.conf /etc/systemd/resolved.conf.d/
sudo systemctl restart systemd-resolved
```

### 02 — Firewall nftables (`modules/02-firewall-nftables/`)

Fuerza todo el DNS por el resolver filtrado y bloquea atajos cifrados:

```bash
sudo cp modules/02-firewall-nftables/files/nftables.conf /etc/nftables.conf
sudo nft -c -f /etc/nftables.conf          # valida antes de aplicar
sudo systemctl restart nftables.service
```

### 03 — Sinkhole DoH (`modules/03-doh-sinkhole/`)

Hace que los nombres de los endpoints DoH resuelvan a loopback:

```bash
sudo sh -c 'cat modules/03-doh-sinkhole/files/hosts.doh-block >> /etc/hosts'
resolvectl flush-caches
```

### 04 — Políticas de navegador (`modules/04-browser-policies/`)

Una fuente única + symlinks + re-aplicación automática:

```bash
sudo install -d /etc/browser-policies
sudo cp modules/04-browser-policies/files/*.json /etc/browser-policies/
sudo cp modules/04-browser-policies/files/browser-doh-lock.conf /etc/tmpfiles.d/
sudo install -d /etc/pacman.d/hooks
sudo cp modules/04-browser-policies/files/99-browser-doh-lock.hook /etc/pacman.d/hooks/
sudo systemd-tmpfiles --create /etc/tmpfiles.d/browser-doh-lock.conf
```

> El hook de `/etc/pacman.d/hooks/` es específico de **Arch**. En otras distros: usa el
> hook nativo de tu gestor o ejecuta `systemd-tmpfiles --create` tras cada instalación
> (systemd ya lo aplica en cada arranque).

### 05 — netguard (`modules/05-netguard/`)

Candado de integridad (golden + `chattr +i` + timer):

```bash
# ver modules/05-netguard/README.md (instala lib, scripts y units)
sudo netguard-lock
```

## Verificación

Después de instalar: [`verification.md`](verification.md).

## Desinstalación

Cada módulo trae su rollback en su README. `netguard` **debe** desarmarse primero si
quieres tocar cualquier archivo protegido:

```bash
sudo netguard-disarm
```
