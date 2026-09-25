# Módulo 03 — DoH y el bootstrap

Cómo DoH esconde las consultas DNS, cuál es su única grieta práctica y por qué bloquearlo
por IP **no** funciona. Este módulo ataca la grieta por **nombre**.

> Implementación → [`modules/03-doh-sinkhole/`](../../modules/03-doh-sinkhole/README.md)

## Glosario del módulo

| Término | Qué significa (en una línea) |
|---|---|
| DoH | DNS over HTTPS: consultas DNS metidas dentro de HTTPS. |
| endpoint | La URL del servidor DoH (`https://…/dns-query`). |
| bootstrap | Resolver *el nombre* del endpoint antes de conectarse a él. |
| sinkhole | Hacer que un nombre resuelva a loopback para que no haya destino. |
| CDN | Red que comparte direcciones IP entre muchísimos sitios. |
| `synthetic` | En `resolvectl`, indicador de que la respuesta salió de datos locales. |

## Mapa de conceptos

```text
  navegador quiere DoH
        │
        ├─(1)─ resolver el NOMBRE del endpoint ──▶ sistema (bootstrap) ← ¡grieta!
        │                                              │
        │                                     si devuelve 127.0.0.1 → sin DoH
        │
        └─(2)─ abrir TLS a la IP del endpoint ──▶ indistinguible de una web
                                                     (por eso NO se bloquea por IP)
```

---

## 1. DoH por dentro

### En una frase

DoH es una consulta DNS normal, empaquetada como una petición HTTPS cualquiera.

### Fundamentos previos

- DNS y filtrado DNS (ver [`00-fundamentos.md`](00-fundamentos.md)).
- HTTPS: TLS en el puerto 443.

### Qué es

Un protocolo (RFC 8484) donde el cliente manda la consulta DNS al endpoint del proveedor
por HTTPS:

```bash
curl -H 'accept: application/dns-json' \
  'https://cloudflare-dns.com/dns-query?name=example.com&type=A'
```

Esa petición devuelve la respuesta DNS (en JSON o en formato binario). Para cualquier
observador de red, es una conexión HTTPS más a Cloudflare.

### Qué problema resuelve

Privacidad e integridad del DNS en redes hostiles: ni el ISP ni la red local pueden ver ni
modificar las consultas. Es una mejora legítima — y la vía más cómoda de saltarse un filtro.

### Cómo funciona paso a paso

1. El cliente decide usar un endpoint (por configuración o default del navegador).
2. **Resuelve el nombre del endpoint** (`cloudflare-dns.com`).
3. Abre TLS a la IP resultante y pide `GET /dns-query?name=…`.
4. Recibe la respuesta y la usa.

El paso 2 es el bootstrap, y es el único punto donde el tráfico todavía depende del
resolver del sistema.

### Qué se rompería sin esto

Nada del proyecto; al contrario, DoH es el motivo de existir de todo esto.

### Error común

**Creer que "bloquear el puerto 443" es una opción.** Es el puerto de casi toda la web:
bloquearlo deja al equipo sin internet. DoH se distingue por **destino**, no por puerto.

### Para profundizar

- RFC 8484 (DoH), RFC 1035 (DNS).

---

## 2. El bootstrap: la única grieta práctica

### En una frase

Para usar DoH, el cliente **primero** tiene que resolver el nombre del endpoint con el
resolver del sistema — y ahí sí se lo puede interceptar.

### Fundamentos previos

- DoH (1), `systemd-resolved` y `ReadEtcHosts` (módulo 01).

### Qué es

El *bootstrap* es esa primera resolución del nombre del endpoint. No es un error de diseño:
es inevitable. El cliente necesita la IP para abrir TLS, y para eso pregunta por el nombre.

### Qué problema resuelve

Entender esto da vuelta el problema: no hace falta "ganarle" a DoH en el tráfico cifrado.
Basta con que el nombre del endpoint **no resuelva a una IP usable**.

### Cómo funciona paso a paso

1. El navegador pregunta al resolver del sistema: "¿`cloudflare-dns.com`?".
2. Si el resolver responde una IP real, el navegador abre TLS y DoH funciona.
3. Si el resolver responde `127.0.0.1` (sinkhole), el navegador intenta conectarse a
   loopback, no encuentra servidor y **falla**.

### Qué se rompería sin esto

El sinkhole del módulo no tendría sobre qué actuar: sin entender el bootstrap, uno intenta
bloquear el tráfico cifrado en vez del paso previo, que es mil veces más fácil.

### Para qué sirve aquí

Es la base de la decisión de diseño: **bloquear DoH por nombre, no por IP**. El nombre está
bajo control del resolver (módulo 01); la IP, no.

### Cómo se usa (archivos reales)

```bash
resolvectl query cloudflare-dns.com
# cloudflare-dns.com: 127.0.0.1 / ::1   (Data from: synthetic)
```

### Error común

**Olvidar que el navegador también puede cachear la IP del endpoint.** Tras cambiar el
sinkhole, un navegador abierto puede seguir usando la IP cacheada un rato. Detectarlo:
reabrir el navegador (`resolvectl flush-caches` y reiniciar el navegador).

### Para profundizar

- [`01-dns-y-resolved.md`](01-dns-y-resolved.md) → concepto 5 (`ReadEtcHosts`).

---

## 3. Por qué fallan las IP-blocklists (CDN compartida)

### En una frase

Los endpoints DoH viven en **la misma CDN** que miles de sitios normales: no se pueden
bloquear por IP sin romper media internet.

### Fundamentos previos

- DoH (1), bootstrap (2).

### Qué es

Cloudflare, Google y otros sirven DoH desde direcciones que **comparten** con sitios
normales. "Bloquear las IPs del endpoint" suena razonable hasta que se resuelven los
nombres y se ve dónde viven.

### Qué problema resuelve

Explica y evita el error más común al intentar bloquear DoH: confiar en una lista de IPs.

### Cómo funciona paso a paso (con datos reales)

1. Se resuelven los endpoints típicos:

   ```text
   one.one.one.one            → 1.1.1.1, 1.0.0.1        ← IPs "canónicas": bloqueables
   dns.google                 → 8.8.8.8, 8.8.4.4        ← bloqueables
   dns.quad9.net              → 9.9.9.9, 149.112.112.112 ← bloqueables
   cloudflare-dns.com         → 104.16.248.249, 104.16.249.249   ← CDN compartida
   mozilla.cloudflare-dns.com → 162.159.61.4, 172.64.41.4        ← CDN compartida
   ```

2. Bloquear las canónicas funciona… hasta que un navegador usa el **nombre** del endpoint
   (que apunta a la CDN) en vez de la IP canónica.
3. Bloquear las IPs de la CDN rompería todos los sitios alojados ahí.

### Qué se rompería sin esto

Si solo bloqueas IPs canónicas, crees estar protegido y no lo estás: Chrome/Firefox usan
`cloudflare-dns.com` / `mozilla.cloudflare-dns.com` por defecto, que apuntan a la CDN.
Detectarlo: `getent ahosts mozilla.cloudflare-dns.com` y comparar con tu lista de bloqueo.

### Para qué sirve aquí

Justifica la capa 3 completa: por eso el bloqueo es por **nombre** y no por IP. Y por eso el
proyecto mantiene **ambas** listas: IPs canónicas (firewall) + nombres (sinkhole).

### Error común

**Ampliar la lista de IPs con rangos de CDN** (`104.16.0.0/12`, `172.64.0.0/13`). Rompe
Cloudflare entero. Es el error que este módulo documenta explícitamente para que nadie lo
cometa "con buena intención".

### Para profundizar

- [`../../docs/threat-model.md`](../../docs/threat-model.md) → "El techo honesto de DoH".

---

## 4. Sinkhole: bloquear por nombre

### En una frase

Si el nombre del endpoint DoH resuelve a loopback, el cliente no tiene a dónde conectarse.

### Fundamentos previos

- Bootstrap (2), `ReadEtcHosts` (módulo 01).

### Qué es

Un *sinkhole* es mapear un nombre a una dirección inútil. Aquí se usa `/etc/hosts`, que
`systemd-resolved` consulta antes de ir a la red (gracias a `ReadEtcHosts=yes`).

### Qué problema resuelve

Corta el bootstrap sin tocar el tráfico cifrado y sin romper CDNs: solo afecta a los nombres
elegidos.

### Cómo funciona paso a paso

1. Se agrega el nombre al bloque `netguard-doh` en `/etc/hosts`:

   ```text
   127.0.0.1 cloudflare-dns.com
   ::1       cloudflare-dns.com
   ```

   Se incluyen **A y AAAA**: si solo se bloqueara IPv4, el cliente podría escapar por IPv6.

2. `resolved` responde desde `/etc/hosts` ("synthetic") sin consultar la red.
3. El cliente intenta conectar a loopback, no hay servidor DoH y falla rápido
   (*connection refused*).

### Qué se rompería sin esto

El bootstrap devolvería la IP real del endpoint (la de la CDN) y el navegador usaría DoH sin
que el firewall — que no bloquea rangos de CDN — pudiera hacer nada.

### Para qué sirve aquí

Es la capa que cierra el hueco que el firewall deja por diseño. Juntas cubren los dos vectores
realistas: IP canónica y nombre de endpoint.

### Cómo se usa (archivos reales)

```bash
resolvectl query cloudflare-dns.com   # → 127.0.0.1
curl -sS -o /dev/null -w '%{http_code}\n' \
  -H 'accept: application/dns-json' \
  'https://cloudflare-dns.com/dns-query?name=example.com&type=A'
# → falla: el endpoint es inalcanzable
```

### Error común

**Bloquear a `0.0.0.0` pensando que es "más seguro".** En Linux, conectarse a `0.0.0.0`
equivale a `127.0.0.1`; usar loopback explícito es más claro y predecible. Otro error:
bloquear nombres que **tu propio resolver usa para DoT** (el SNI de validación): no rompe la
conexión (se conecta por IP), pero confunde al depurar. Documentar la lista evita sorpresas.

### Para profundizar

- `man 5 hosts`, [`../../docs/verification.md`](../../docs/verification.md).

---

## 5. Límites y el puente al módulo 04

### En una frase

Bloquear por nombre cubre a los navegadores reales, pero no a una IP grabada ni a apps con
su propio resolver: eso queda para la política del módulo 04.

### Fundamentos previos

- Todo lo anterior.

### Qué es

La enumeración honesta de lo que este módulo **no** puede:

- Un cliente con la **IP del endpoint hardcodeada** no necesita el bootstrap.
- Una app con su **propio stack DNS** (algunos clientes VPN) no usa `resolved`.
- Un proveedor **no listado** sobrevive hasta que se agregue su nombre.

### Qué problema resuelve

Saber dónde termina esta capa y por qué existe la siguiente. Sin esta honestidad, se cree
que el sinkhole "resuelve DoH" cuando solo cubre su vector principal.

### Cómo funciona paso a paso

1. El sinkhole corta el bootstrap por nombre (el caso de Chrome/Firefox por defecto).
2. Si el software decide no usar DoH (política), se cubre el caso de la IP fija.
3. Si ni eso: es un límite conocido, documentado, no un bug.

### Qué se rompería sin esto

Nada técnico. Pero se perdería la honestidad del proyecto: prometer "bloqueo total" cuando
hay vectores que ninguna configuración local puede cerrar sin interceptar TLS.

### Para qué sirve aquí

Es el puente entre la estrategia de red (módulos 02–03) y la de software (módulo 04). La
pregunta cambia de "¿puedo ver el paquete?" a "¿puedo evitar que se genere?".

### Cómo se usa (archivos reales)

```bash
grep -c 'BEGIN netguard-doh' /etc/hosts   # la lista es finita y auditable
```

### Error común

**Sumar nombres sin criterio** (por ejemplo, bloquear todo lo que "suene a DNS"). Cada
nombre bloqueado es un servicio que deja de funcionar. La lista debe ser mínima y
justificada: solo endpoints DoH que no quieres que se usen.

### Para profundizar

- Siguiente: [`04-politicas-navegador.md`](04-politicas-navegador.md).

---

## Relación entre estos conceptos

```text
DoH (1)            →  el problema: DNS escondido en HTTPS
   │
   ├─ bootstrap (2)   →  la grieta: el nombre se resuelve antes
   │
   ├─ CDN (3)         →  por qué NO se bloquea por IP
   │
   └─ sinkhole (4)    →  la solución por nombre
            │
            └─ límites (5)  →  lo que queda para el módulo 04
```

El orden importa: (1) define el problema, (2) encuentra la grieta, (3) descarta la vía
equivocada, (4) explota la grieta y (5) delimita el alcance real.
