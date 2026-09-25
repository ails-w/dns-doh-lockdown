# Fundamentos

Antes de los módulos: el vocabulario y el problema que todo el proyecto intenta resolver.
Si entiendes este archivo, el resto se lee solo.

## Glosario global

| Término | Qué significa (en una línea) |
|---|---|
| **DNS** | El sistema que traduce nombres (`example.com`) a direcciones IP. |
| **resolver** | El componente que hace esa traducción; puede ser local o remoto. |
| **resolver del sistema** | El punto único por el que resuelve un equipo Linux (`systemd-resolved`). |
| **NSS** | Capa de glibc que decide *por dónde* se resuelve un nombre (`/etc/nsswitch.conf`). |
| **stub resolver** | Resolver local de `systemd-resolved` en `127.0.0.53`. |
| **DoT** | DNS over TLS: cifra las consultas DNS en el puerto 853. |
| **DoH** | DNS over HTTPS: esconde las consultas dentro de HTTPS (puerto 443). |
| **bootstrap** | Primer paso de DoH: resolver *el nombre* del endpoint DoH con el resolver del sistema. |
| **CDN** | Red de servidores que comparte IPs entre muchísimos sitios (Cloudflare, Google). |
| **nftables** | El sistema de filtrado de paquetes del kernel Linux (reemplazo de iptables). |

## Mapa de conceptos

```text
   DNS ──usa──▶ resolver del sistema ──puede ser──▶ filtrado (Families)
     │                    │
     │                    └── puede cifrarse con ──▶ DoT
     │
     └── puede esconderse con ──▶ DoH ──▶ ¡rompe el filtrado!
                    │
                    └── se ataca en 3 frentes:
                          por IP      → firewall      (módulo 02)
                          por nombre  → sinkhole      (módulo 03)
                          por software→ política      (módulo 04)
                    y todo se protege con → integridad (módulo 05)
```

---

## 1. DNS

### En una frase

DNS es la guía telefónica de internet: convierte un nombre legible en la dirección IP que
las máquinas necesitan.

### Fundamentos previos

Nada. Es la base.

### Qué es

Cada vez que abres un sitio, tu equipo necesita la IP detrás de ese nombre. DNS es el
protocolo (y la red de servidores) que responde esa pregunta. Está diseñado **en claro**:
la consulta viaja sin cifrar por el puerto 53, y por eso cualquiera en el camino (tu ISP,
la red Wi-Fi) puede verla y hasta modificarla.

### Qué problema resuelve

Sin DNS tendrías que memorizar direcciones IP. Es una de las piezas más viejas y más
críticas de internet.

### Cómo funciona paso a paso

1. Una app pregunta por `example.com` (vía `getaddrinfo`).
2. El sistema busca en `/etc/hosts` primero y, si no está, consulta a un resolver.
3. El resolver pregunta a la jerarquía DNS (raíz → TLD → dominio) y devuelve la IP.
4. La app se conecta a esa IP.

### Qué se rompería sin esto

Todo. Ninguna app encuentra a nadie. Pero el punto del proyecto no es "que funcione", es
**dónde** se hace la pregunta y **quién** puede verla.

### Para qué sirve aquí

Todo el proyecto gira alrededor de un único punto de resolución controlable. Si no puedes
concentrar el DNS, no puedes filtrarlo ni auditarlo.

### Error común

Creer que "DNS" es "el servidor DNS". Son **tres** cosas distintas: el cliente (resolver),
el protocolo (consultas) y los servidores (respuestas). Confundirlas hace imposible
razonar sobre fugas.

---

## 2. Filtrado DNS y su fragilidad

### En una frase

Puedes filtrar por DNS (bloquear dominios maliciosos), pero es un filtro **cooperativo**
que se salta fácil.

### Fundamentos previos

- DNS (concepto 1).

### Qué es

Consiste en usar un resolver que responde `0.0.0.0` (o nada) a dominios catalogados como
malware, phishing o contenido no deseado. El proyecto usa **Cloudflare for Families**
(`1.1.1.3`), pero cualquier resolver con filtrado sirve.

### Qué problema resuelve

Bloquea publicidad, malware y categorías enteras para **todo el equipo**, sin instalar nada
por app. Es barato, centralizado y fácil de auditar.

### Cómo funciona paso a paso

1. La app pregunta por un dominio.
2. El resolver filtrado consulta su lista de categorías.
3. Si está bloqueado, devuelve una dirección nula (`0.0.0.0`).
4. La app no puede conectarse.

### Qué se rompería sin esto

El equipo resolvería por cualquier servidor, incluyendo dominios maliciosos, y no habría
punto de control.

### Error común

**Confiar en el filtro como si fuera una barrera.** Un DNS filtrado asume que *todo* pasa
por él. Cualquier app que traiga su propio resolver, o que use DoH, lo esquiva sin tocar
una sola configuración.

### Para profundizar

- Módulo 01 (resolver) y módulo 02 (firewall): lo que hace que el filtro se respete.

---

## 3. DoH: el bypass que motivó todo el proyecto

### En una frase

DoH esconde las consultas DNS dentro de HTTPS normal, así que tu filtro deja de verlas.

### Fundamentos previos

- DNS (1) y filtrado DNS (2).
- HTTPS: el puerto 443, donde viaja casi toda la web cifrada.

### Qué es

**DNS over HTTPS** empaqueta cada consulta DNS dentro de una petición HTTPS y la manda a un
endpoint del proveedor (por ejemplo `https://cloudflare-dns.com/dns-query`). Para la red,
es idéntico a visitar una web: puerto 443, TLS, tráfico cifrado.

### Qué problema resuelve

Privacidad real: ni tu ISP ni la red local pueden ver ni modificar tus consultas. Es una
mejora legítima de privacidad — y también la forma más cómoda de saltarse cualquier filtro.

### Cómo funciona paso a paso (y dónde está la grieta)

1. El navegador quiere usar DoH contra `https://cloudflare-dns.com/dns-query`.
2. **Antes de conectarse, tiene que resolver el nombre `cloudflare-dns.com`.** Ese primer
   paso usa tu resolver del sistema: eso es el **bootstrap**.
3. Resuelto el nombre, abre TLS a la IP del endpoint y ya no consulta en claro nunca más.

La grieta para bloquearlo está en el paso 2: el bootstrap pasa por tu resolver.

### Qué se rompería sin esto

Nada del proyecto; al contrario. Sin DoH no habría problema que resolver. El proyecto
**existe** por DoH.

### Error común

**Intentar bloquear DoH por IP.** Los endpoints viven en CDN compartida: bloquear
`104.16.x` (Cloudflare) o `162.159.x` rompe miles de sitios normales. Este es el error
central que el proyecto demuestra y resuelve por capas.

### Para profundizar

- Módulo 03 (bloqueo por nombre) y módulo 04 (política del navegador): las dos formas que
  sí funcionan.
- `docs/threat-model.md` → "El techo honesto de DoH".

---

## 4. La respuesta: defensa en profundidad

### En una frase

En vez de buscar *el* bloqueo perfecto (no existe), se apilan cinco capas donde cada una
tapa el hueco de la anterior.

### Fundamentos previos

- Todo lo anterior.

### Qué es

Un esquema donde ninguna capa es suficiente por sí sola:

| Capa | Pregunta que responde | Módulo |
|---|---|---|
| Resolver | ¿Qué se resuelve? | 01 |
| Firewall | ¿Por dónde se puede preguntar? | 02 |
| Sinkhole | ¿Puede el navegador encontrar su endpoint DoH? | 03 |
| Política | ¿El software *decide* no usar DoH? | 04 |
| Integridad | ¿Alguien desactivó lo anterior? | 05 |

### Cómo funciona paso a paso

1. El resolver filtra y cifra todo lo que sí pasa por él.
2. El firewall fuerza a que **todos** los caminos pasen por el resolver, y cierra los
   atajos conocidos (DoT a terceros, DoH a IPs canónicas).
3. El sinkhole corta el bootstrap de DoH **por nombre**.
4. La política del navegador cubre el caso que la red no puede: una IP fija grabada.
5. La integridad evita que todo lo anterior se desactive en silencio.

### Qué se rompería sin esto

Cada capa sola deja un hueco demostrable: el resolver se salta con DoH, el firewall no ve
DoH por 443, el sinkhole no ve una IP grabada, la política no cubre apps que no la leen.
Juntas, no hay un bypass trivial que sobreviva a las cinco.

### Error común

**Creer que "más capas" es redundancia.** No lo es: cada capa cubre un vector distinto.
Quitar una no es "ahorrar": es reabrir un bypass concreto.

### Para profundizar

- [`../architecture.md`](../architecture.md) — cómo encajan técnicamente.
- [`../threat-model.md`](../threat-model.md) — qué protege y qué **no**.
- Empieza por el módulo [`01-dns-y-resolved.md`](01-dns-y-resolved.md).
