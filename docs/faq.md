# Preguntas frecuentes

## Alcance

**¿Funciona fuera de Arch Linux?**
Sí en su mayor parte. `systemd-resolved`, `nftables`, `/etc/hosts` y `systemd-tmpfiles` son
estándar en cualquier distro con systemd. Lo único específico de Arch es el **hook de
pacman**; en Debian/Fedora se reemplaza por un hook del gestor o simplemente se ejecuta
`systemd-tmpfiles --create` (los módulos se re-aplican igual en cada arranque).

**¿Puedo usar un solo módulo?**
Sí. Cada módulo en `modules/` es autocontenido. Lo más común es querer solo el 02
(firewall) o solo el 05 (`netguard`) sobre una config que ya tienes.

**¿Esto es seguridad o autocontrol?**
Autocontrol, principalmente. Está diseñado para que **tu propio equipo** no se salte tu
filtro. Contra un atacante con root no es una barrera. Ver
[`threat-model.md`](threat-model.md).

## DNS

**¿Por qué Cloudflare for Families y no otro?**
Porque ofrece filtrado (malware + contenido adulto) sobre DoT con un hostname estable, y
es fácil de forzar por firewall. Puedes cambiarlo: ajusta `DNS=` en el módulo 01 y la IP
en el módulo 02. Solo asegúrate de que el firewall apunte al mismo resolver.

**¿Sirve si ya uso Pi-hole / AdGuard Home en la red?**
Sí, y es complementario: apunta el módulo 01 a tu resolver local y deja que el firewall
fuerce todo hacia él. La lógica de capas no cambia.

**¿Por qué no bloquear rangos enteros de Cloudflare?**
Porque esas IPs son **CDN compartida**: bloquearlas rompe miles de sitios legítimos. Por
eso DoH se bloquea **por nombre** (capa 3), no por rango.

**¿Y si uso una VPN?**
Puede traer su propio DNS y cifrado, y potencialmente su propio transporte. Revísalo caso
por caso; el DNAT de `:53` y el bloqueo de DoT/DoH aplican igual al tráfico del equipo.

**¿Rompe el Wi-Fi de hoteles/aeropuertos?**
Los portales cautivos pueden fallar. Solución temporal en
[`troubleshooting.md`](troubleshooting.md) (parar nftables, autenticarse, reanudar).

## Navegadores

**¿Qué navegadores cubre la capa 4?**
Toda la familia Chromium (Brave, Chrome, Chromium, Edge, Vivaldi, …) y Firefox. Los forks
de Firefox (LibreWolf, Zen, …) requieren añadir su ruta `distribution/policies.json`.

**¿Y los navegadores Flatpak?**
No leen las políticas del host: viven en un sandbox con su propio `/etc`. Configúralos
aparte (es un límite conocido).

## netguard

**`chattr +i` no es peligroso, ¿y si quiero editar?**
Es *fricción a propósito*, no un candado permanente. El flujo previsto es
`netguard-disarm` → editar → `netguard-lock` → `start`. Documentado en
`modules/05-netguard/README.md`.

**¿Por qué `netguard` está separado de focusguard?**
Porque son ciclos de vida distintos: `focusguard` bloquea *usuarios por horario*;
`netguard` protege *archivos de configuración*. Comparten el patrón (golden + inmutabilidad
+ integridad) pero no deben compartir el interruptor: editar la red no debe desarmar tu
bloqueo de usuario.

**¿Qué pasa si alguien (o yo) borra los logs?**
Nada bueno, y ese es justamente el punto: `netguard` no puede impedir que root borre
`/var/log/netguard/audit.log`; solo deja rastro de lo que vigila. Si necesitas logs
inmutables, considera enviarlos fuera del equipo.
