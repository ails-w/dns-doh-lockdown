# Modelo de amenaza

Documentar lo que un sistema **no** protege es tan importante como documentar lo que sí.
Este archivo es el contrato honesto de `dns-doh-lockdown`.

## Supuesto de diseño

Está pensado para el caso **"no quiero que mi propio equipo se salte el filtro DNS"**
(autocontrol, control parental, cumplimiento doméstico). **No** está pensado como muro
contra un atacante con root, y no pretende serlo.

## Qué protege

| Escenario de bypass | Qué lo detiene | Capa |
|---|---|---|
| Un navegador con DoH activado | política gestionada (`DnsOverHttpsMode: off`) | 4 |
| DoH por nombre (`cloudflare-dns.com`, `dns.google`, …) | sinkhole en `/etc/hosts` | 3 |
| DoH por IP canónica (`1.1.1.1`, `8.8.8.8`, …) | firewall, `drop` en 443 | 2 |
| DNS en claro a un servidor arbitrario (`8.8.8.8:53`) | DNAT forzado a `1.1.1.3` | 2 |
| DoT a un tercero (`9.9.9.9:853`) | firewall, `drop` en 853 | 2 |
| DNS desde una **VM** o un **contenedor** | `prerouting` + `forward` | 2 |
| Fuga por **IPv6** | paridad v4/v6 en filtro y NAT | 2 |
| Edición accidental/silenciosa de la config | `netguard` (golden + `chattr +i`) | 5 |
| Desactivación oportunista ("hoy lo apago un rato") | fricción de `netguard-disarm` | 5 |

## Qué NO protege

| Límite | Por qué |
|---|---|
| **Root decidido** | root puede `chattr -i`, parar timers, editar el golden, borrar logs. `chattr +i` es fricción, no frontera. |
| **DoH con IP hardcodeada a un endpoint no listado** | DoH viaja por 443 y es indistinguible de HTTPS normal. Sin interceptar TLS no hay forma genérica de bloquearlo. |
| **DoH hacia un rangos de CDN compartidos** | No se pueden bloquear sin romper sitios legítimos alojados en la misma CDN. |
| **Apps con su propio stack DNS** | Algunas apps (VPN, clientes propietarios) traen su propio resolver y no usan `getaddrinfo`. |
| **Navegadores Flatpak/Snap** | Viven en un sandbox con su propio `/etc`: no ven las políticas del host. |
| **VPN / túnel propio** | Puede traer su propio DNS y su propio cifrado; revisar caso por caso. |
| **Nuevos proveedores DoH** | La lista de nombres es finita. Un proveedor exótico no listado sobrevive hasta que se agregue. |

## El techo honesto de DoH

Hay tres formas de intentar frenar DoH, y solo dos funcionan de forma general:

1. **Bloquear por IP.** Falla: las IPs del endpoint están en CDN compartida.
2. **Bloquear por nombre.** Funciona para el *bootstrap*, que es como navegadores y apps
   normales resuelven el endpoint. Se evade con una IP fija grabada.
3. **Que el software decida no usarlo.** Es la única que cubre el caso 2. Por eso la
   capa 4 (políticas) no es redundante: cubre exactamente lo que la red no puede.

## Endurecimiento adicional (fuera de alcance)

Si necesitas una barrera real y no fricción, hay que mover el control **fuera del
alcance del usuario**:

- Sacar `sudo`/`wheel` al usuario que quieres limitar.
- Mover el filtrado a la **red** (router, Pi-hole, firewall perimetral) o a un gateway
  controlado (p. ej. Cloudflare Zero Trust), no al host.
- Sacar el hardware de tu alcance (móvil gestionado, cuenta sin privilegios).

Estas medidas no se implementan aquí a propósito: cambian el modelo de confianza del
equipo y salen del objetivo del proyecto.
