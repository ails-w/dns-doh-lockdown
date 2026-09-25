# Módulo 02 — Firewall nftables

Cómo el kernel decide qué paquetes salen, entran o se reenvían — y cómo se usa para
**forzar** que todo el DNS pase por el resolver filtrado. Es la capa que convierte una
configuración en una imposición.

> Implementación → [`modules/02-firewall-nftables/`](../../modules/02-firewall-nftables/README.md)

## Glosario del módulo

| Término | Qué significa (en una línea) |
|---|---|
| netfilter | El framework de filtrado de paquetes dentro del kernel Linux. |
| nftables | La herramienta/sintaxis moderna para configurar netfilter (`nft`). |
| hook | Punto del recorrido de un paquete donde netfilter puede intervenir. |
| cadena base | Cadena enganchada a un hook; por ahí pasa el tráfico real. |
| prioridad | Orden en que se evalúan las cadenas de un mismo hook. |
| verdict | Decisión sobre un paquete: `accept`, `drop`, `jump`, … |
| tabla | Contenedor de cadenas (p. ej. `inet dnsguard`). |
| conntrack | Seguimiento de conexiones del kernel (`established`, `related`). |
| NAT | Traducción de direcciones/puertos; incluye DNAT y masquerade. |
| bridge | Interfaz virtual que agrupa tráfico (Docker, libvirt). |

## Mapa de conceptos

```text
  paquete
     │
     ▼
  HOOK (prerouting → routing → input/forward → output → postrouting)
     │
     ├─ cadenas base ordenadas por PRIORIDAD
     │        │
     │        └─ verdict: accept NO es final · drop SÍ es final
     │
     ├─ NAT: reescribe destino (DNAT) o fuente (masquerade)
     │
     └─ TABLAS: propias (dnsguard_*) vs compartidas (filter/nat) ← decisión de diseño
```

---

## 1. Netfilter y los hooks

### En una frase

El kernel tiene "puntos de control" por donde pasa cada paquete, y nftables te deja poner
reglas en ellos.

### Fundamentos previos

Nada de red. Solo la idea de que un paquete es un sobre con origen, destino y puertos.

### Qué es

**netfilter** es el mecanismo del kernel; **nftables** es cómo se le habla. Un paquete
recorre el stack de red pasando por cinco puntos (`hooks`): `prerouting`, `input`,
`forward`, `output` y `postrouting`.

### Qué problema resuelve

Sin esto, el kernel no tendría forma de filtrar ni de reescribir tráfico: cualquier conexión
entraría o saldría sin control.

### Cómo funciona paso a paso

1. El paquete llega a la interfaz → `prerouting` (antes de decidir su ruta).
2. El kernel decide: ¿es para este equipo (`input`) o va a otro (`forward`)?
3. Si es local, sube al proceso; si va a otro, se reenvía.
4. El tráfico generado localmente pasa por `output`.
5. Antes de salir por la interfaz, `postrouting`.

### Qué se rompería sin esto

No habría firewall: cualquier app podría hablar con cualquier cosa. Tampoco habría forma de
redirigir el DNS.

### Para qué sirve aquí

Es el sustrato de toda la capa 2. La clave: `output` ve lo que genera *tu equipo* y
`forward` ve lo que **atraviesa** (VMs, contenedores). El proyecto necesita reglas en ambos.

### Error común

**Pensar que `output` cubre todo.** El tráfico de una VM o de un contenedor **no** pasa por
`output`: pasa por `forward`. Si solo filtras `output`, una VM puede hacer DoH libremente.

### Para profundizar

- `man 5 nft`, wiki de nftables ("Netfilter hooks").

---

## 2. Tablas, cadenas y prioridades (la regla de oro)

### En una frase

Puede haber varias cadenas en el mismo hook; se evalúan por prioridad y **un `drop` en
cualquiera gana**, aunque otra cadena haya aceptado.

### Fundamentos previos

- Hooks (1).

### Qué es

Una **cadena base** se engancha a un hook con una **prioridad** (número; menor = antes).
Varias cadenas (incluso de tablas distintas) pueden colgar del mismo hook. Los *verdicts*
deciden el destino del paquete: `accept` deja pasar (pero **no** cancela las cadenas
posteriores), `drop` lo descarta **inmediatamente** y detiene toda evaluación.

### Qué problema resuelve

Permite combinar reglas de varios orígenes (tu firewall, Docker, libvirt) sin que se pisen.
Pero obliga a entender la semántica real, que sorprende a quien viene de iptables.

### Cómo funciona paso a paso

1. El paquete entra a un hook.
2. Se evalúan las cadenas en orden de prioridad.
3. `accept` termina **esa** cadena y pasa a la siguiente.
4. `drop` termina **todo**: el paquete muere.
5. El paquete se acepta solo si **ninguna** cadena lo dropeó.

### Qué se rompería sin esto

Este proyecto usa esa semántica a propósito: su cadena `forward` acepta los bridges de
Docker/libvirt **y** dropea DoT/DoH, sabiendo que el `drop` es final y global. Entender
mal la regla hace que tu firewall "no haga nada" o bloquee de más.

### Para qué sirve aquí

Es el porqué de varias decisiones del módulo: el orden de las reglas dentro de la cadena
(los `drop` antes de los `accept`) y por qué una cadena propia puede bloquear tráfico que
otro programa aceptó.

### Cómo se usa (archivos reales)

```nft
chain forward {
    type filter hook forward priority filter; policy drop
    # los drops van ANTES de los accept: dentro de una cadena, accept corta la evaluación
    meta l4proto { tcp, udp } th dport 853 drop
    ip  daddr $DOH4 meta l4proto { tcp, udp } th dport 443 drop
    ...
    iifname "virbr*" accept
}
```

### Error común

**Asumir que `accept` es final (como en iptables).** No lo es entre cadenas base del mismo
hook. Detectarlo: pones un `accept` y el tráfico sigue bloqueado por otra tabla
(Docker, libvirt o tu propia cadena).

### Para profundizar

- `man 5 nft`, secciones "Chains" y "Verdicts".

---

## 3. NAT: DNAT en `output` y `prerouting`

### En una frase

DNAT reescribe el **destino** de un paquete: es la herramienta que hace que "cualquier DNS"
termine, sin que la app lo sepa, en el resolver filtrado.

### Fundamentos previos

- Hooks (1), cadenas (2).

### Qué es

**NAT** = traducción de direcciones de red. En su forma **DNAT** (*destination NAT*) cambia
la dirección/puerto destino. Vive en cadenas de **tipo `nat`**, con prioridad anterior al
filtrado.

### Qué problema resuelve

Una app que hardcodea `8.8.8.8:53` no usa tu resolver: se le puede redirigir el destino a
`1.1.1.3` sin que se entere ni tenga que cooperar.

### Cómo funciona paso a paso

1. Sale un paquete UDP/TCP con destino `:53` a cualquier IP.
2. Se evalúa la cadena `nat output` (tráfico local) o `nat prerouting` (tráfico reenviado).
3. Se reescribe el destino a `1.1.1.3` (conntrack recuerda la traducción).
4. El paquete sigue su camino hacia Cloudflare Families.

### Qué se rompería sin esto

Toda app con DNS propio o hardcodeado resolvería por donde quiera, salteándose el filtro.
Con DNAT, no importa lo que pida: termina en el resolver filtrado.

### Para qué sirve aquí

Es el "DNS forzado" del módulo. Se aplica en dos puntos:

- `output` → el tráfico del propio equipo (excluyendo loopback, donde vive el stub).
- `prerouting` para `virbr*` / `docker0` / `br-*` → el DNS de VMs y contenedores.

### Cómo se usa (archivos reales)

```nft
table ip dnsguard_nat {
  chain prerouting {
    type nat hook prerouting priority -100; policy accept
    iifname $BRIDGES meta l4proto { udp, tcp } th dport 53 dnat to 1.1.1.3
  }
  chain output {
    type nat hook output priority -100; policy accept
    ip daddr 127.0.0.0/8 return
    meta l4proto { udp, tcp } th dport 53 dnat to 1.1.1.3
  }
}
```

### Error común

**Olvidar el `return` de loopback.** Sin `ip daddr 127.0.0.0/8 return`, el DNAT también
"redirige" las consultas al stub `127.0.0.53` — que va a sí mismo — y el DNS se rompe en
silencio. Otra: usar DNAT para `:53` **y también** olvidar el tráfico reenviado
(`prerouting`), dejando a las VMs fuera del forzado.

### Para profundizar

- `man 5 nft`, secciones "NAT" y prioridades; RFC 3022 (NAT).

---

## 4. Tablas propias (`dnsguard_*`) vs compartidas

### En una frase

Usa **tus** tablas, no las estándar (`filter`/`nat`), porque otros programas también las
escriben y recargar puede borrarles las reglas.

### Fundamentos previos

- Tablas y cadenas (2), NAT (3).

### Qué es

Una decisión de diseño: el archivo de este módulo define `table inet dnsguard`,
`table ip dnsguard_nat` y `table ip6 dnsguard_nat`, en lugar de escribir en las tablas
"históricas" `filter` y `nat`.

### Qué problema resuelve

Docker escribe su NAT en `ip nat`; libvirt, o bien usa tablas propias (`ip libvirt_network`),
o bien `ip filter`/`ip nat`. Si tu archivo empieza con `destroy table ip nat`, al recargar
**borras la NAT de Docker** y los contenedores se quedan sin red.

### Cómo funciona paso a paso

1. Un archivo que dice `destroy table ip nat` borra **toda** la tabla, con las cadenas de
   quien sea.
2. Al recargar `nftables.service` (o aplicar tu archivo), Docker pierde su NAT.
3. Con tablas propias, el `destroy` solo afecta a las tuyas.
4. Recargar es seguro e idempotente.

### Qué se rompería sin esto

La prueba concreta: con la VM encendida, recargar el firewall hace que se quede sin internet
hasta reiniciar su red. Con tablas propias, no.

### Para qué sirve aquí

Es lo que hace al módulo seguro de recargar — y lo que permitió que `netguard` (módulo 05)
pueda recargar el firewall tras restaurar el archivo.

### Cómo se usa (archivos reales)

```nft
destroy table inet dnsguard   # solo borra la tuya
destroy table ip  dnsguard_nat
destroy table ip6 dnsguard_nat
```

### Error común

**Reutilizar `ip nat` "porque es donde va el NAT".** Funciona hasta que otro programa
(Docker, libvirt) confía en esa tabla. Detectarlo: contenedores/VM sin red tras recargar
nftables.

### Para profundizar

- [`../../docs/architecture.md`](../../docs/architecture.md) → "Coexistencia con otros manejadores de red".

---

## 5. `forward`, bridges e IPv6

### En una frase

El tráfico de VMs y contenedores se **reenvía** (no es `output`), y el IPv6 necesita su
propia paridad de reglas.

### Fundamentos previos

- Hooks (1), cadenas (2), NAT (3).

### Qué es

La cadena `forward` filtra lo que **atraviesa** el equipo: paquetes de una VM o de un
contenedor hacia internet. Además, el filtro es `inet` (dual-stack: IPv4 **e** IPv6), así
que las reglas deben considerar ambos.

### Qué problema resuelve

Sin `forward` no puedes aplicar la política a VMs/contenedores. Sin IPv6, todo lo anterior
solo aplica a la mitad del tráfico.

### Cómo funciona paso a paso

1. Un contenedor manda un paquete.
2. El kernel lo marca como *forward* (viene de `docker0`, va a `wlan0`).
3. Se evalúa la cadena `forward`: debe **aceptar** los bridges, y **dropear** DoT/DoH.
4. El NAT de Docker hace el *masquerade* de salida.

### Qué se rompería sin esto

- Sin aceptar los bridges: Docker/VMs sin red.
- Sin el drop de DoT/DoH en `forward`: una VM se saltea el bloqueo que el host sí tiene.
- Sin `ip6`/`ip6 daddr`: con IPv6 habilitado, DoH y DNS v6 se escapan.

### Para qué sirve aquí

Es lo que hace que la política del módulo sea **universal en la máquina**, no solo para el
tráfico del host.

### Cómo se usa (archivos reales)

```nft
iifname { "docker0", "br-*" } accept
oifname { "docker0", "br-*" } accept
ip6 daddr $DOH6 meta l4proto { tcp, udp } th dport 443 drop
```

### Error común

**Creer que IPv6 es "opt-in" del todo.** Aunque hoy no tengas IPv6 global, el kernel la tiene
habilitada y el tráfico de *link-local* existe. Si algún día una VPN o el router provee v6,
las reglas v4 no cubren nada. Detectarlo: `ip -6 route` con rutas globales que no esperabas.

### Para profundizar

- `man 5 nft` (familia `inet` y `ip6`), [`../../docs/threat-model.md`](../../docs/threat-model.md).

---

## Relación entre estos conceptos

```text
hooks (1)  →  dónde se puede actuar
   │
   └─ cadenas + prioridades (2)  →  cómo se combinan las reglas (accept no final, drop global)
            │
            ├─ NAT (3)              →  fuerza el DNS al resolver filtrado
            ├─ tablas propias (4)   →  permite recargar sin romper a otros
            └─ forward + IPv6 (5)   →  extiende la política a VMs, contenedores y v6
```

El orden importa: (1) y (2) son el modelo mental; (3) es la función principal del módulo;
(4) es la decisión de diseño que lo hace seguro de operar; (5) es su cobertura total.
