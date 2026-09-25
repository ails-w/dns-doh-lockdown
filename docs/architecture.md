# Arquitectura

`dns-doh-lockdown` es una cadena de **cinco capas independientes** que, juntas, evitan
que el tráfico DNS de un equipo Linux se escape por DoH — o por cualquier otro camino
que salte tu resolver.

La idea de diseño: **ninguna capa por sí sola alcanza**, y cada una cubre el punto
ciego de la anterior.

## Las cinco capas

| # | Módulo | Qué hace | Dónde vive |
|---|--------|----------|------------|
| 1 | `01-resolved-dns` | resuelve con filtrado + cifrado (DoT) | `/etc/systemd/resolved.conf.d/` |
| 2 | `02-firewall-nftables` | fuerza todo DNS por la capa 1; bloquea DoT/DoH alternativos | `/etc/nftables.conf` |
| 3 | `03-doh-sinkhole` | mata el *bootstrap* de DoH **por nombre** | `/etc/hosts` |
| 4 | `04-browser-policies` | el navegador **ni lo intenta** (política gestionada) | `/etc/*/policies/` |
| 5 | `05-netguard` | candado de integridad de todo lo anterior | `/usr/local/…` + systemd |

Cada módulo se puede adoptar por separado; juntos forman una cadena donde cada capa
existe porque la anterior tiene un límite.

## Cómo encajan

```text
        app ──getaddrinfo()──▶ nsswitch ──▶ 127.0.0.53 (stub)
                                                   │
                                                   ▼
                                          systemd-resolved
                                                   │
                        ┌──────────────────────────┴──────────────────────────┐
                        ▼                                                     ▼
                /etc/hosts (sinkhole)                               1.1.1.3 vía DoT
                responde 127.0.0.1                                  (Cloudflare Families)
                a los nombres DoH
```

Y para el tráfico que **no** pasa por el resolver (apps que hardcodean un servidor):

```text
        app ──▶ 8.8.8.8:53      ──(nftables nat prerouting/output)──▶ 1.1.1.3:53
        app ──▶ 9.9.9.9:853     ──(nftables filter output)─────────▶ drop
        app ──▶ 8.8.8.8:443     ──(nftables filter output)─────────▶ drop
        app ──▶ cloudflare-dns.com:443 ──(/etc/hosts)──────────────▶ 127.0.0.1 (sin servidor)
```

## Responsabilidad de cada capa

1. **Resolver (1).** Único punto de resolución. Filtra (Cloudflare for Families),
   cifra en tránsito (DoT) y no tiene fallback: si no puede con el filtro, no resuelve.
2. **Firewall (2).** Convierte la política en *ley del kernel*. Redirige todo `:53` a
   `1.1.1.3`, cierra DoT a terceros y bloquea DoH hacia IPs canónicas. Cubre también a
   VMs y contenedores (su tráfico va por `forward`, no por `output`).
3. **Sinkhole (3).** Los endpoints DoH viven en CDN compartida (Cloudflare, Google), así
   que no se pueden bloquear por IP sin romper media internet. Se bloquean **por nombre**:
   el navegador no puede resolver el endpoint, así que no puede conectarse.
4. **Políticas (4).** Última frontera que la red no puede cubrir: un DoH contra una IP
   fija no genera un nombre que envenenar ni una IP que no rompa nada. Si el navegador
   **decide no hacer DoH** (`DnsOverHttpsMode: off`), no hay paquete que bloquear.
5. **Integridad (5).** Todo lo anterior vive en archivos editables por root. `netguard`
   guarda una copia *golden*, los marca inmutables (`chattr +i`) y los restaura si
   cambian. No es una frontera: es **fricción + reversión + auditoría**.

## Coexistencia con otros manejadores de red

El firewall usa **tablas propias** (`dnsguard`, `dnsguard_nat`) en lugar de las tablas
compartidas `filter`/`nat`. Motivo: recargar `nftables.service` no debe borrar las reglas
de Docker ni de libvirt. La cadena `forward` acepta explícitamente los bridges de VM
(`virbr*`) y de contenedores (`docker0`, `br-*`).

> Detalle: libvirt moderna usa su propia tabla nftables (`ip libvirt_network`), mientras
> que Docker usa `ip filter` / `ip nat` (vía `iptables-nft`). Las tablas `dnsguard_*`
> conviven con ambas.

## Modelo de amenaza

Qué protege y qué **no** → [`threat-model.md`](threat-model.md).
