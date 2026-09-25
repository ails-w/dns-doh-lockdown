# Aprendizaje

Conceptos del proyecto, **un archivo por módulo**. Se leen en orden: cada uno se entiende
solo, pero juntos explican todo el sistema.

| Módulo | Archivo | Qué aprenderás |
|---|---|---|
| — | [`00-fundamentos.md`](00-fundamentos.md) | glosario global, mapa de capas, el problema de DoH |
| 01 | [`01-dns-y-resolved.md`](01-dns-y-resolved.md) | DNS, NSS, systemd-resolved, DoT |
| 02 | [`02-firewall-nftables.md`](02-firewall-nftables.md) | netfilter/nftables, hooks, cadenas, NAT, tablas propias |
| 03 | [`03-doh-y-bootstrap.md`](03-doh-y-bootstrap.md) | DoH, el *bootstrap*, por qué fallan las IP-blocklists |
| 04 | [`04-politicas-navegador.md`](04-politicas-navegador.md) | políticas *managed*, Chromium vs Firefox, tmpfiles, hooks |
| 05 | [`05-integridad-netguard.md`](05-integridad-netguard.md) | `chattr +i`, golden, el patrón lock/integrity/disarm |

## Esquema de cada concepto

Siempre el mismo, para poder **escanear** sin leer todo:

- **En una frase** — la idea mínima, sin jerga.
- **Fundamentos previos** — lo que hay que entender antes; se explica ahí mismo.
- **Qué es** — definición desarrollada. Explicar, no nombrar.
- **Qué problema resuelve** — el dolor concreto sin esto.
- **Cómo funciona paso a paso** — la mecánica, numerada.
- **Qué se rompería sin esto** — contrafactual concreto de *este* proyecto.
- **Para qué sirve aquí** / **Cómo se usa (archivos reales)**.
- **Error común** — qué se hace mal y cómo detectarlo.
- **Para profundizar** — referencias y conceptos relacionados.

## Reglas

- Se acumula: los conceptos aprendidos **nunca** se borran.
- Glosario + mapa de conceptos son obligatorios al inicio de cada archivo.
- Cada concepto debe tener su **Error común**: es lo que demuestra comprensión real.
- Plantilla para un módulo nuevo: [`template.md`](template.md).
