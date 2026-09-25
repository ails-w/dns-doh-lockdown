# Módulo 04 — Políticas de navegador

Cómo forzar que un navegador **no intente** usar DoH, con un mecanismo que las empresas
usan para gestionar miles de equipos: políticas gestionadas. Es la única capa que cubre el
caso que la red no puede: un DoH contra una IP fija.

> Implementación → [`modules/04-browser-policies/`](../../modules/04-browser-policies/README.md)

## Glosario del módulo

| Término | Qué significa (en una línea) |
|---|---|
| política gestionada | Ajuste impuesto por un archivo del sistema que el usuario no puede cambiar. |
| `managed/` | Carpeta de políticas **obligatorias** en los navegadores Chromium. |
| `recommended/` | Carpeta de políticas **sugeridas** (el usuario puede cambiarlas). |
| `policies.json` | Archivo único de políticas de Firefox. |
| `DnsOverHttpsMode` | Política de Chromium que controla DoH (`off`/`automatic`/`secure`). |
| `network.trr.mode` | Preferencia equivalente en Firefox (`5` = DoH apagado). |
| `systemd-tmpfiles` | Gestor declarativo de archivos y symlinks de systemd. |
| hook de pacman | Script que pacman ejecuta según qué paquetes se instalan/actualizan. |

## Mapa de conceptos

```text
  política gestionada (1)  →  el mecanismo: archivos que el navegador obedece
        │
        ├─ Chromium vs Firefox (2)  →  dos formatos, dos rutas
        │
        └─ despliegue
              ├─ fuente única + symlinks (3)  →  no duplicar contenido
              ├─ systemd-tmpfiles (4)         →  crear/reparar en cada arranque
              └─ hook de pacman (5)           →  re-aplicar al instalar
        │
        └─ límites (6)  →  Flatpak, duplicados, forks
```

---

## 1. Política gestionada

### En una frase

Un archivo que el navegador lee al arrancar y **obedece aunque el usuario no quiera**;
el usuario ni siquiera puede cambiar el ajuste desde la interfaz.

### Fundamentos previos

Nada de navegadores. La idea de "configuración impuesta por el sistema" es la misma que
`/etc` en general.

### Qué es

Los navegadores serios (Chromium, Firefox) tienen un sistema de políticas para empresas:
archivos JSON de propiedad de root, en rutas fijas, con dos niveles:

- **`managed/`** → obligatorio. El control en Ajustes queda bloqueado/gris.
- **`recommended/`** → sugerido. El usuario puede cambiarlo.

### Qué problema resuelve

Permite a un administrador fijar configuraciones que el usuario no puede (ni debe) cambiar.
En este proyecto, el "administrador" eres tú, y el "usuario" es tu yo del futuro.

### Cómo funciona paso a paso

1. El navegador arranca y busca políticas en su ruta fija.
2. Lee **todos** los `.json` de la carpeta y los **fusiona** en un diccionario.
3. Aplica lo que entiende y registra un error por cada clave que no conoce.
4. La política queda visible en `chrome://policy` (o `about:policies` en Firefox).

### Qué se rompería sin esto

Este es el punto del módulo: si el navegador no decide "no usar DoH", una IP fija grabada no
genera ningún paquete bloqueable. Sin política, esa vía queda abierta por diseño.

### Para qué sirve aquí

Es la capa 4: cierra el hueco que las capas de red admiten en `docs/threat-model.md`.

### Cómo se usa (archivos reales)

```json
{ "DnsOverHttpsMode": "off" }
```

### Error común

**Poner políticas Brave-específicas (`BraveRewardsDisabled`, etc.) en las carpetas de otros
navegadores.** Cada clave desconocida aparece como error en `chrome://policy`. Por eso este
proyecto separa la fuente genérica (`chromium-doh-off.json`) de las políticas propias de
cada marca.

### Para profundizar

- Chrome Enterprise policy list; Mozilla "policy templates".

---

## 2. Chromium vs Firefox: dos formatos, dos rutas

### En una frase

Cada familia de navegadores compila **su propia ruta** y usa **su propio formato**: no hay
un archivo universal.

### Fundamentos previos

- Políticas gestionadas (1).

### Qué es

- **Familia Chromium** (Brave, Chrome, Chromium, Edge, Vivaldi…): carpeta
  `policies/managed/` dentro de su directorio de marca (`/etc/brave/…`, `/etc/opt/chrome/…`),
  con JSON plano.
- **Firefox**: un único archivo `policies.json` (típicamente
  `/etc/firefox/policies/policies.json`) con la forma `{"policies": {…}}`.

### Qué problema resuelve

Entender la diferencia permite desplegar la misma intención en cualquier navegador sin
adivinar. La ruta se fija al compilar el navegador: no es configurable.

### Cómo funciona paso a paso

1. Chromium: lee `…/policies/managed/*.json` y fusiona.
2. Firefox: lee `policies.json` y aplica `{"policies": {...}}`.
3. Firefox además permite `"Locked": true`, que **bloquea** la preferencia en `about:config`
   (en Chromium, `managed/` ya es obligatorio por sí solo).

### Qué se rompería sin esto

El error clásico: escribir la política de Firefox con el formato de Chromium (sin el
envoltorio `policies`), o ponerla en la carpeta equivocada. No falla ruidosamente: el
navegador simplemente la ignora.

### Para qué sirve aquí

Justifica que el módulo instale archivos distintos para cada familia, desde una sola fuente
conceptual.

### Cómo se usa (archivos reales)

```json
{
  "policies": {
    "DNSOverHTTPS": { "Enabled": false, "Locked": true }
  }
}
```

### Error común

**Esperar que Vivaldi o Opera lean exactamente la misma ruta que Chrome.** Vivaldi compila
`/etc/chromium/policies` en algunas versiones; Opera no soporta bien el sistema. Por eso el
config cubre varias rutas: es más barato cubrir de más que adivinar.

### Para profundizar

- [`../verification.md`](../verification.md) — comprobar con `brave://policy`.

---

## 3. Fuente única + symlinks

### En una frase

El contenido real existe **una sola vez**; cada navegador ve un enlace a él.

### Fundamentos previos

- Chromium vs Firefox (2).

### Qué es

Los archivos canónicos viven en `/etc/browser-policies/`. Cada carpeta de navegador tiene un
**symlink** (`00-doh-off.json` → `/etc/browser-policies/chromium-doh-off.json`).

### Qué problema resuelve

Sin esto tendrías N copias del mismo JSON: actualizas una y te olvidas de las otras. El
symlink hace que un cambio se propague a todos y que un candado de integridad (módulo 05)
proteja a todos de golpe.

### Cómo funciona paso a paso

1. El navegador abre `…/managed/00-doh-off.json`.
2. El kernel resuelve el symlink y lee el archivo real.
3. Actualizas el archivo real una vez → todos los navegadores ven el cambio.

### Qué se rompería sin esto

Con copias, la configuración se desincroniza. El síntoma típico: un navegador con DoH
apagado y otro no, "sin motivo".

### Para qué sirve aquí

Es el patrón DRY aplicado a configuración de sistema, y lo que hace trivial el candado del
módulo 05.

### Cómo se usa (archivos reales)

```bash
readlink -f /etc/brave/policies/managed/00-doh-off.json
# /etc/browser-policies/chromium-doh-off.json
```

### Error común

**Candar el symlink en vez del destino.** Un `chattr +i` sobre el enlace no protege el
contenido. En este proyecto se protege el **archivo real** (módulo 05).

### Para profundizar

- `man 7 symlink`.

---

## 4. `systemd-tmpfiles` y hooks de pacman

### En una frase

`systemd-tmpfiles` crea y repara los symlinks en cada arranque; el hook de pacman los
re-aplica en el momento en que instalas o actualizas algo.

### Fundamentos previos

- Fuente única + symlinks (3).

### Qué es

- **`systemd-tmpfiles`**: herramienta declarativa que asegura que existan directorios,
  archivos y symlinks según un archivo de configuración (`d` = directorio, `L+` = symlink
  forzado). Se aplica **en cada arranque** (`systemd-tmpfiles-setup.service`).
- **Hook de pacman**: archivo en `/etc/pacman.d/hooks/` con un `[Trigger]` y una `[Action]`.
  Con `Type = Package` + `Target = *` corre tras **cualquier** transacción.

### Qué problema resuelve

Los paquetes de navegador recrean sus carpetas al instalarse. Sin re-aplicación, el symlink
desaparece al actualizar y DoH vuelve. Estas dos piezas garantizan que la política se
restaure sin intervención.

### Cómo funciona paso a paso

1. `systemd-tmpfiles --create` procesa el archivo: crea `…/managed/` y el enlace.
2. En cada arranque, systemd lo vuelve a hacer (idempotente).
3. Al instalar/actualizar un paquete, pacman corre el hook → mismo resultado, al instante.
4. Instalas Firefox, Chrome o lo que sea: queda cubierto sin tocar nada.

### Qué se rompería sin esto

Actualizas Brave y pierdes la política. Te enteras meses después, cuando ves DoH activo en
`brave://policy` sin recordar por qué.

### Para qué sirve aquí

Convierte la configuración en algo **auto-reparable** en el tiempo. Es la mitad "sistemas"
del proyecto: entender que la config de un equipo no es un archivo, es un estado que hay que
mantener.

### Cómo se usa (archivos reales)

```text
d /etc/brave/policies/managed 0755 root root -
L+ /etc/brave/policies/managed/00-doh-off.json - - - - /etc/browser-policies/chromium-doh-off.json
```

### Error común

**Poner `L` en vez de `L+`.** `L+` fuerza el reemplazo; `L` no garantiza reemplazar un
archivo existente. Otro: creer que el hook corre en el arranque (no: corre en transacciones
de pacman; del arranque se encarga `tmpfiles`).

### Para profundizar

- `man 5 tmpfiles.d`, `man 5 alpm-hooks`.

---

## 5. Límites: Flatpak, duplicados y forks

### En una frase

Esta capa cubre los navegadores que leen políticas del sistema; no cubre sandboxes ni
proveedores no contemplados.

### Fundamentos previos

- Todo lo anterior.

### Qué es

Los bordes reales del módulo:

- **Flatpak/Snap**: el navegador corre en un sandbox con su propio `/etc`; no ve estas
  políticas.
- **Duplicados**: dos archivos en la misma carpeta `managed/` con la misma clave dejan el
  resultado a merced del orden de fusión (no garantizado).
- **Forks de Firefox** (LibreWolf, Zen, Floorp): usan su propia ruta `distribution/`;
  requieren una línea más en el tmpfiles.
- **Opera**: soporte incompleto del sistema de políticas.

### Qué problema resuelve

Saber dónde no llega la capa evita falsas sensaciones de cobertura y permite planificar el
caso (configurar aparte, agregar ruta, etc.).

### Cómo funciona paso a paso

1. Un navegador de repositorio (`pacman`) → cubierto.
2. Un Flatpak → no cubierto; hay que configurarlo dentro del sandbox.
3. Un fork → agregar su par `d`/`L+` con su ruta.

### Qué se rompería sin esto

Un Flatpak de Chromium con DoH activo pasaría por todas las capas sin que ninguna lo note —
salvo que la red lo frene (y ya sabes que eso no siempre alcanza).

### Para qué sirve aquí

Cierra la documentación del módulo con honestidad: la capa 4 es fuerte donde aplica, y
conviene saber exactamente dónde aplica.

### Cómo se usa (archivos reales)

```bash
# Comprobar si un navegador lee la política:
# abrir chrome://policy (o brave://policy) y buscar DnsOverHttpsMode
```

### Error común

**Asumir que "instalé el navegador con pacman, entonces está cubierto"** sin verificar en
`chrome://policy`. Verificar siempre: es la única prueba directa.

### Para profundizar

- [`../../docs/faq.md`](../../docs/faq.md) → Flatpak y forks.
- Siguiente: [`05-integridad-netguard.md`](05-integridad-netguard.md).

---

## Relación entre estos conceptos

```text
política gestionada (1)  →  el mecanismo que cubre la IP hardcodeada
        │
        ├─ formatos por familia (2)  →  Chromium vs Firefox
        │
        └─ despliegue
              ├─ fuente única (3)     →  DRY
              ├─ tmpfiles (4a)        →  repara en cada arranque
              ├─ hook pacman (4b)     →  repara al instalar
              └─ límites (5)          →  Flatpak, forks, duplicados
```

El orden importa: (1) es el porqué, (2) el cómo por familia, (3)–(4) el cómo mantenerlo vivo
en el tiempo, y (5) hasta dónde llega de verdad.
