# Módulo 05 — Integridad (netguard)

Cómo evitar que todo lo anterior se desactive en silencio. No es una frontera: es
**fricción + reversión + auditoría** — y entender por qué *no* es una frontera es tan
importante como entender cómo funciona.

> Implementación → [`modules/05-netguard/`](../../modules/05-netguard/README.md)

## Glosario del módulo

| Término | Qué significa (en una línea) |
|---|---|
| inodo | La estructura del sistema de archivos que describe un archivo (dueño, permisos, atributos). |
| atributo | Bandera extra del inodo, aparte de los permisos `rwx`. |
| `chattr` / `lsattr` | Cambiar / consultar atributos de archivo. |
| `+i` | *immutable*: no se puede modificar, borrar ni renombrar **ni como root**. |
| golden | Copia "buena" de un archivo, referencia para restaurar. |
| drift | Diferencia entre el estado actual y el golden. |
| oneshot | Servicio de systemd que corre, hace su trabajo y termina. |
| timer | Unidad de systemd que dispara otra según un horario. |

## Mapa de conceptos

```text
  chattr +i (1)  →  hace que editar sea deliberado
        │
        ▼
  patrón golden (2)  →  ¿cómo se detecta y revierte un cambio?
        │
        ├─ timer cada minuto (3)  →  cuándo se revisa
        │
        ├─ decisiones (4)         →  lista única, self-skip, golden por ruta
        │
        └─ fricción vs frontera (5)  →  qué garantiza y qué no
```

---

## 1. `chattr +i`: atributos de inodo

### En una frase

`chmod` controla **permisos**; `chattr` controla **atributos**, y `+i` hace que ni root
pueda cambiar el archivo sin quitar la bandera primero.

### Fundamentos previos

- Nada especial: la idea de "atributo de archivo" es autónoma.

### Qué es

Los atributos son banderas guardadas en el **inodo**, al nivel del sistema de archivos. Los
relevantes:

| Atributo | Efecto |
|---|---|
| `+i` | inmutable: no modificar, borrar ni renombrar |
| `+a` | append-only: solo agregar al final |
| `-i` / `-a` | quitar la bandera |

### Qué problema resuelve

Añade una capa más fuerte que `rwx`: incluso un proceso root necesita un paso deliberado
(`chattr -i`) antes de poder editar. Ese paso es lo que deja **rastro y fricción**.

### Cómo funciona paso a paso

1. `chattr +i archivo` marca el inodo.
2. Cualquier escritura, borrado o renombrado falla con `Operation not permitted`.
3. Para editarlo: `chattr -i archivo`, editar, `chattr +i archivo`.
4. `lsattr archivo` muestra la `i` en su columna de atributos.

### Qué se rompería sin esto

Editar la configuración sería tan fácil como borrar un carácter. La reversión automática
igual funcionaría, pero sin el freno previo: cambiar y arrepentirse no costaría nada.

### Para qué sirve aquí

Es la mitad "fricción" de la capa 5: no impide el cambio, lo hace **deliberado**.

### Cómo se usa (archivos reales)

```bash
lsattr /etc/nftables.conf
# ----i----------------- /etc/nftables.conf
```

### Error común

**Creer que `+i` protege contra root.** No: root tiene `CAP_LINUX_IMMUTABLE` y puede
quitarlo. `+i` protege contra ediciones accidentales, scripts ingenuos y — sobre todo —
contra ti en un momento débil. Confundirlo con una frontera es el error que este módulo
existe para desmentir.

### Para profundizar

- `man 1 chattr`, `man 1 lsattr`; capacidad `CAP_LINUX_IMMUTABLE`.

---

## 2. El patrón golden: lock → detectar → restaurar

### En una frase

Guardas una copia buena, marcas el original como inmutable y, cada minuto, comparas: si
cambió, lo restauras y lo vuelves a bloquear.

### Fundamentos previos

- `chattr +i` (1).

### Qué es

Un patrón de tres piezas:

- **golden**: la copia de referencia, también inmutable.
- **lock**: toma la foto del estado actual y bloquea.
- **integrity**: compara golden vs. actual; si difieren, restaura y re-bloquea.

### Qué problema resuelve

`chattr +i` solo hace difícil el primer cambio. Este patrón hace que, si el cambio ocurre
igual, **se revierta solo** en menos de un minuto y quede registrado.

### Cómo funciona paso a paso

1. `netguard-lock` recorre la lista: quita `i`, copia el archivo al golden, vuelve a marcar
   ambos.
2. `netguard-integrity` corre cada minuto: por cada archivo con golden, compara con `cmp`.
3. Si difieren: restaura desde el golden, re-bloquea y registra en el log.
4. Si difiere solo la bandera (alguien quitó `i`): la vuelve a poner (rama *relock*).
5. Si el archivo restaurado era de red/DNS, recarga el servicio correspondiente.

### Qué se rompería sin esto

Una edición pasaría desapercibida hasta que surfearas algo que debía estar bloqueado. El
sistema "parece" configurado, pero su estado real cambió.

### Para qué sirve aquí

Es el corazón de la capa 5 y la razón de ser del módulo: convertir la configuración en un
estado **verificable y auto-reparable**.

### Cómo se usa (archivos reales)

```bash
sudo netguard-lock                                # foto + bloqueo
sudo systemctl start netguard-integrity.service   # verificación puntual
sudo journalctl -t netguard -n 5                  # "integrity-restore file=…"
```

### Error común

**Editar un archivo protegido sin desarmar.** La integridad lo revierte en ≤1 minuto y
parece "un bug". El flujo correcto está en el README del módulo:
`disarm → editar → lock → start`.

### Para profundizar

- [`../../modules/05-netguard/README.md`](../../modules/05-netguard/README.md).

---

## 3. systemd: `oneshot` + `timer`

### En una frase

No hay un daemon residente: un *timer* dispara un *service* `oneshot` cada minuto, que corre
y muere.

### Fundamentos previos

- El patrón golden (2).

### Qué es

- **`.service` con `Type=oneshot`**: se ejecuta, termina y no queda en memoria.
- **`.timer`**: dispara el service según un horario (`OnCalendar`).

### Qué problema resuelve

Correr tareas periódicas sin mantener un proceso vivo, sin `cron` y con logs integrados en
`journald`.

### Cómo funciona paso a paso

1. `OnCalendar=*-*-* *:*:45` → se dispara en el segundo 45 de cada minuto.
2. `systemd` arranca el service como root.
3. El script corre, registra y sale.
4. `AccuracySec=1s` evita que systemd agrupe disparos y los corra tarde.

### Qué se rompería sin esto

La verificación solo correría cuando alguien la ejecutara a mano: exactamente cuando menos
te acordás de hacerlo.

### Para qué sirve aquí

Es el "cómo" temporal del módulo. Nota de vocabulario: **no es un daemon** (no hay proceso
residente); son timers + scripts.

### Cómo se usa (archivos reales)

```bash
systemctl list-timers netguard-integrity.timer
journalctl -t netguard -n 5
```

### Error común

**Poner la ruta del `ExecStart` a mano y equivocarse.** El service falla con `203/EXEC` y
el timer sigue "activo": nada se revisa y no hay aviso obvio. Detectarlo:
`systemctl status netguard-integrity.service`.

### Para profundizar

- `man 5 systemd.timer`, `man 5 systemd.service`.

---

## 4. Decisiones de implementación (y por qué)

### En una frase

Tres decisiones evitan bugs sutiles: lista única, golden por ruta completa y auto-skip solo
al restaurarse.

### Fundamentos previos

- El patrón golden (2), timers (3).

### Qué es

Decisiones tomadas al escribir `netguard` que conviene entender para no revertirlas sin
querer:

1. **Lista única** (`files.sh`) usada por lock e integrity → imposible que se desincronicen.
2. **Golden por ruta completa** (`_etc_hosts`) → evita colisiones de `basename` entre rutas
   distintas.
3. **Solo se gestiona lo que tiene golden** → integrity nunca bloquea algo que no puede
   restaurar.
4. **Auto-skip al restaurar** → integrity nunca reescribe el script que se está ejecutando
   (sobrescribir un script en ejecución corrompe a bash).

### Qué problema resuelve

Cada una evita un bug real: configs fantasma, goldens pisados, archivos bloqueados sin
respaldo, corrupción del propio guardián.

### Cómo funciona paso a paso

1. `files.sh` define `NG_FILES` una vez.
2. `lock` e `integrity` la sourcean.
3. `golden_path` convierte la ruta en nombre de archivo seguro.
4. `integrity` salta `$0` en la rama de restauración, pero sí se re-bloquea con `chattr`.

### Qué se rompería sin esto

Ejemplo concreto: si `integrity` no se saltara a sí mismo, al restaurar su golden se
sobrescribiría mientras corre → bash lee líneas corruptas → fallo intermitente
dificilísimo de depurar.

### Para qué sirve aquí

Es la parte que convierte un script de 20 líneas en algo que se puede dejar corriendo meses.

### Cómo se usa (archivos reales)

```bash
grep -n 'NG_FILES' modules/05-netguard/files/lib/netguard/files.sh
```

### Error común

**Duplicar la lista** en lock e integrity "por claridad". Es la receta para que un archivo
quede sin vigilar: agregas una ruta en uno y olvidas el otro.

### Para profundizar

- Git history de `modules/05-netguard/`.

---

## 5. Fricción, no frontera (y por qué va separado de focusguard)

### En una frase

`netguard` no impide desactivar la protección; hace que desactivarla **cueste, se revierta
y quede registrado** — y vive separado de cualquier otro sistema de bloqueo.

### Fundamentos previos

- Todo lo anterior.

### Qué es

La postura honesta del módulo:

- **No es una frontera**: root puede `chattr -i`, parar timers, editar goldens, borrar logs.
- **Es fricción**: `netguard-disarm` exige `sudo`, escribir una frase y esperar 60 segundos.
- **Es reversión**: lo que se cambie sin desarmar, se restaura.
- **Es auditoría**: cada acción queda en `/var/log/netguard/audit.log` y en `journald`.

Y está **separado** de un sistema de bloqueo de usuarios a propósito.

### Qué problema resuelve

Dos ciclos de vida distintos:

- Un bloqueo de usuario cambia seguido (horarios) y su "desarmar" significa *permitir uso*.
- La integridad de la red casi no cambia y su "desarmar" significa *poder editar*.

Si compartieran interruptor, editar el firewall desarmaría tu bloqueo de usuario (y al
revés). Ese acoplamiento es el bug conceptual que la separación evita.

### Cómo funciona paso a paso

1. `netguard-disarm` → pide `sudo` (sujeto a tus propias reglas de PAM, si las tienes),
   exige la frase `desarmar red` y espera 60 s.
2. Detiene el timer y quita la inmutabilidad.
3. Editas, y con `netguard-lock` fijas la nueva golden.
4. Cada paso queda auditado.

### Qué se rompería sin esto

Ya sea un "desarmar" demasiado fácil (perderías la protección sin pensarlo) o un acoplamiento
entre módulos (tocar red afectaría tu horario). Ambas cosas son peores que el bloqueo en sí.

### Para qué sirve aquí

Es la filosofía del proyecto, aplicada al proyecto: los sistemas de autocontrol funcionan
cuando son **deliberados y reversibles**, no cuando prometen ser inviolables.

### Cómo se usa (archivos reales)

```bash
sudo netguard-disarm         # sudo + frase + 60 s
sudo tail /var/log/netguard/audit.log
```

### Error común

**Vender esto como "a prueba de balas".** Genera falsa seguridad y, peor, expectativas
equivocadas. La promesa correcta es: *"desactivarlo es deliberado, se revierte solo y queda
registrado"*.

### Para profundizar

- [`../../docs/threat-model.md`](../../docs/threat-model.md) → "Qué NO protege".
- Proyecto hermano: el mismo patrón aplicado a bloqueo de usuarios (focusguard/focusblock).

---

## Relación entre estos conceptos

```text
chattr +i (1)  →  fricción por archivo
      │
      └─ golden + timer (2, 3)  →  reversión automática
               │
               ├─ decisiones (4)  →  que no tenga bugs sutiles
               └─ postura (5)     →  qué promete y qué no
```

El orden importa: (1) frena; (2) y (3) revierten; (4) hace el sistema confiable en el
tiempo; (5) define honestamente el alcance de todo lo anterior.
