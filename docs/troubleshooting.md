# Troubleshooting

Síntoma → causa probable → arreglo.

## Red y resolución

| Síntoma | Causa probable | Arreglo |
|---|---|---|
| Tras instalar la capa 1, **nada resuelve** | la red bloquea 853 y 53 al upstream, o el resolver elegido no responde | probar `resolvectl query example.com`; temporalmente `DNSOverTLS=no`; verificar que `1.1.1.3` sea alcanzable |
| El **portal cautivo** (hotel/aeropuerto) no carga | el DNS forzado rompe el portal | `sudo systemctl stop nftables.service` → autenticarse → `sudo systemctl start nftables.service` |
| **mDNS/LLMNR** dejó de funcionar (impresoras, casting, `.local`) | el `input drop` corta 5353/5355 | añadir en la cadena `input`: `udp dport { 5353, 5355 } accept` y recargar |
| Hay **consultas DNS** que no van a `1.1.1.3` | fuga (app con resolver propio, o regla faltante) | `sudo tcpdump -ni <iface> 'port 53'`; revisar DNAT en `prerouting`/`output` |

## Virtualización

| Síntoma | Causa probable | Arreglo |
|---|---|---|
| La **VM** pierde internet tras recargar nftables | se destruyó/regeneró una tabla compartida (versión vieja con `destroy table ip nat`) | usar tablas propias (`dnsguard_*`); verificar con `sudo nft list tables` |
| El **contenedor Docker** no resuelve | falta `accept` del bridge en `forward` | confirmar el nombre real del bridge (`ip -brief addr`) y que esté en la lista (`docker0`, `br-*`) |
| Docker dejó de publicar puertos | la NAT de Docker fue pisada | no usar `destroy table ip nat`; revisar `sudo nft list chain ip nat PREROUTING` |

## Navegadores

| Síntoma | Causa probable | Arreglo |
|---|---|---|
| La política **no aparece** | carpeta equivocada para esa marca, o navegador no reiniciado | revisar `chrome://policy`; confirmar ruta; reiniciar el navegador |
| La **política se perdió** tras actualizar | el gestor de paquetes recreó la carpeta | `sudo systemd-tmpfiles --create /etc/tmpfiles.d/browser-doh-lock.conf`; verificar el hook |
| Un navegador **Flatpak/Snap** ignora la política | corre en sandbox con su propio `/etc` | no usa estas políticas; configurarlo aparte |
| DoH sigue funcionando en un navegador | IP hardcodeada o app con stack DNS propio | límite conocido → ver [`threat-model.md`](threat-model.md) |

## netguard

| Síntoma | Causa probable | Arreglo |
|---|---|---|
| `Operation not permitted` al editar un archivo | `chattr +i` | `sudo netguard-disarm` (o `sudo chattr -i <archivo>`) |
| Mis cambios **se revierten solos** | editaste sin desarmar; la integridad restauró desde golden | flujo correcto: `disarm` → editar → `netguard-lock` → `start` |
| `netguard-integrity.service` falla con **203/EXEC** | ruta equivocada en `ExecStart` (typo) | revisar la unit: `systemctl cat netguard-integrity.service` |
| `netguard-lock` no crea goldens | falta `cp -a` en `golden_lock_one`, o el golden dir no existe | `ls -A /var/lib/netguard/golden/`; revisar la lib |
| No sé qué hizo | — | `sudo journalctl -t netguard -n 20` y `sudo tail /var/log/netguard/audit.log` |

## Filosofía de diagnóstico

1. **Aísla la capa.** ¿Falla la resolución, el firewall, el sinkhole, la política o la integridad? Cada una tiene su prueba en [`verification.md`](verification.md).
2. **Mira el log antes de tocar.** `journalctl -t netguard`, `resolvectl status`, `sudo nft list ruleset`.
3. **Desarma con el flujo previsto**, no a mano: si editas archivos inmutables "porque sí", la integridad los revertirá y te confundirá más.
