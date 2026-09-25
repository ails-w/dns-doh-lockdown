# Módulo 02 — Firewall nftables

Convierte la política de DNS en **ley del kernel**: fuerza todo `:53` hacia el resolver
filtrado, cierra DoT a terceros y bloquea DoH hacia las IPs canónicas. Cubre también el
tráfico de **VMs y contenedores**.

## Prerrequisitos

- `nftables` instalado; servicio `nftables.service` disponible.
- Un resolver al que forzar el DNS (por defecto `1.1.1.3`, Cloudflare for Families).

## Archivos

| Archivo | Destino | Qué hace |
|---|---|---|
| `files/nftables.conf` | `/etc/nftables.conf` | filtro dual-stack + NAT forzado, en tablas propias |

## Aplicar

```bash
sudo cp files/nftables.conf /etc/nftables.conf
sudo nft -c -f /etc/nftables.conf            # valida SIN aplicar
sudo systemctl enable --now nftables.service
sudo systemctl restart nftables.service
```

## Verificar

```bash
sudo nft list tables | grep dnsguard
sudo nft list ruleset | sed -n '/table inet dnsguard/,/^}/p'
```

Batería completa: [`../../docs/verification.md`](../../docs/verification.md).

## Rollback

Este módulo no toca tablas compartidas, así que revertir es borrar **solo las suyas**:

```bash
sudo nft delete table inet dnsguard
sudo nft delete table ip dnsguard_nat
sudo nft delete table ip6 dnsguard_nat
```

## Notas de diseño

- **Tablas propias (`dnsguard_*`) en vez de `filter`/`nat`.** Motivo: recargar
  `nftables.service` no debe borrar las reglas de Docker ni las de libvirt. Un
  `destroy table ip nat` en un archivo compartido se lleva por delante la NAT de Docker.
- **Docker y VMs.** La cadena `forward` acepta explícitamente `virbr*` (libvirt),
  `docker0` y `br-*` (Docker). El DNS de VMs/contenedores se fuerza en `prerouting`, porque
  su tráfico **no** pasa por `output`.
- **IPv6.** El filtro es `inet` (dual-stack) y el NAT tiene su tabla `ip6`. Hoy es
  preventivo: solo actúa si hay conectividad IPv6 real.
- **DoT:** se permite solo hacia `1.1.1.3`/`1.0.0.3` (TCP 853) y se corta todo lo demás,
  incluido `udp 853` (DoQ).
- **DoH:** se bloquean las IPs canónicas de los proveedores conocidos. Los endpoints
  alojados en CDN se cubren **por nombre** en el módulo 03; un DoH con IP hardcodeada
  contra un endpoint no listado queda fuera del alcance (ver `docs/threat-model.md`).
- **mDNS/LLMNR:** el `input drop` los corta. Si los necesitas, agrega antes del final de
  la cadena `input`:
  `udp dport { 5353, 5355 } accept`
- **Portal cautivo:** si un portal de hotel/aeropuerto no carga, `sudo systemctl stop
  nftables.service`, autentícate y vuelve a arrancarlo.
