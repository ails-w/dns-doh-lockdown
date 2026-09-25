# Módulo 01 — Resolved DNS

Deja el resolver del sistema **filtrado** (Cloudflare for Families) y **cifrado** (DoT),
sin fallback. Es la capa que decide *qué* se resuelve.

## Prerrequisitos

- `systemd-resolved` activo.
- `/etc/resolv.conf` apuntando al stub (`/run/systemd/resolve/stub-resolv.conf`).
- root.

## Archivos

| Archivo | Destino | Qué hace |
|---|---|---|
| `files/00-cloudflare-family.conf` | `/etc/systemd/resolved.conf.d/` | DNS Family + DoT + DNSSEC, sin fallback |
| `files/10-read-etc-hosts.conf` | `/etc/systemd/resolved.conf.d/` | fuerza `ReadEtcHosts=yes` (lo necesita el módulo 03) |

## Aplicar

```bash
sudo install -d /etc/systemd/resolved.conf.d
sudo cp files/00-cloudflare-family.conf files/10-read-etc-hosts.conf /etc/systemd/resolved.conf.d/
sudo systemctl restart systemd-resolved
```

> Si tu `/etc/resolv.conf` no apunta al stub:
> `sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf`

## Verificar

```bash
resolvectl status
resolvectl query example.com                 # IP real, "Data from: network"
resolvectl query nudity.testcategory.com     # Filtered/Censored
```

Detalle completo: [`../../docs/verification.md`](../../docs/verification.md).

## Rollback

```bash
sudo rm /etc/systemd/resolved.conf.d/00-cloudflare-family.conf
sudo rm /etc/systemd/resolved.conf.d/10-read-etc-hosts.conf
sudo systemctl restart systemd-resolved
```

## Notas

- `DNS=` fija `1.1.1.3` / `1.0.0.3`: **Cloudflare for Families** (malware + contenido adulto).
  Si usas otro resolver, ajusta **también** la IP del módulo 02 (firewall) para que apunten al
  mismo sitio.
- `FallbackDNS=` vacío es deliberado: sin él, el sistema podría resolver por un servidor no
  filtrado cuando el principal falla.
- `DNSOverTLS=opportunistic`: cifra si puede; si la red bloquea `853`, cae a DNS en claro
  **que el firewall igual redirige a `1.1.1.3`**.
- El sufijo `#cloudflare-dns.com` es el nombre para validar el certificado DoT: **no** se
  resuelve por DNS.
- `10-read-etc-hosts.conf` parece trivial, pero es lo que permite que el sinkhole del módulo 03
  funcione: sin `ReadEtcHosts=yes`, `resolved` no consultaría `/etc/hosts`.
