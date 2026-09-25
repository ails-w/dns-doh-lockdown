# Módulo 05 — netguard

Candado de **integridad** para los archivos de configuración de los módulos anteriores:
guarda una copia *golden*, los marca inmutables (`chattr +i`) y los restaura si alguien
(o *el tú del futuro*) los cambia. Es el módulo que va **al final**, porque congela el
estado ya correcto de todo lo demás.

## Qué es (y qué no es)

`netguard` es **fricción + reversión + auditoría**, no una frontera. Un root decidido puede
`chattr -i`, parar timers y borrar logs. Lo que aporta es que desactivarlo sea
**deliberado, se revierta solo y quede registrado**.

Está **separado de focusguard** a propósito: son ciclos de vida distintos. Editar la red
no debe desarmar tu bloqueo de usuario, ni al revés.

## Prerrequisitos

- `systemd`, `e2fsprogs` (`chattr`/`lsattr`), `util-linux` (`logger`).
- Los módulos 01–04 instalados (o ajusta la lista de archivos protegidos).

## Archivos

| Archivo | Destino |
|---|---|
| `files/lib/guard/golden.sh` | `/usr/local/lib/guard/golden.sh` |
| `files/lib/netguard/files.sh` | `/usr/local/lib/netguard/files.sh` |
| `files/bin/netguard-lock` | `/usr/local/bin/netguard-lock` |
| `files/bin/netguard-integrity` | `/usr/local/bin/netguard-integrity` |
| `files/bin/netguard-disarm` | `/usr/local/bin/netguard-disarm` |
| `files/units/netguard-integrity.service` | `/etc/systemd/system/` |
| `files/units/netguard-integrity.timer` | `/etc/systemd/system/` |

## Aplicar

```bash
sudo install -d /usr/local/lib/guard /usr/local/lib/netguard
sudo install -m 0644 files/lib/guard/golden.sh /usr/local/lib/guard/golden.sh
sudo install -m 0644 files/lib/netguard/files.sh /usr/local/lib/netguard/files.sh
sudo install -m 0755 files/bin/netguard-lock files/bin/netguard-integrity files/bin/netguard-disarm /usr/local/bin/
sudo install -m 0644 files/units/netguard-integrity.service files/units/netguard-integrity.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now netguard-integrity.timer

# Primera foto del estado bueno + bloqueo:
sudo netguard-lock
```

## Flujo para cambiar algo protegido

```bash
sudo netguard-disarm                        # baja el timer y desbloquea
#   editar los archivos...
sudo netguard-lock                          # nueva golden + bloquear
sudo systemctl start netguard-integrity.timer
```

> No reinicies entre `disarm` y `lock`: si el timer vuelve a activarse, la integridad
> restauraría la golden vieja y perderías los cambios. Es el comportamiento querido.

## Verificar

```bash
lsattr /etc/nftables.conf /etc/hosts /etc/browser-policies/*.json   # todos con 'i'
ls -A /var/lib/netguard/golden/ | wc -l                             # # de archivos protegidos

# Prueba de reversión (sabotaje controlado):
sudo chattr -i /etc/hosts
sudo sh -c 'echo "# sabotage" >> /etc/hosts'
sudo systemctl start netguard-integrity.service
tail -3 /etc/hosts      # "# sabotage" desaparece
lsattr /etc/hosts       # vuelve a tener 'i'
sudo journalctl -t netguard -n 5 --no-pager
```

## Rollback

```bash
sudo netguard-disarm
sudo systemctl disable --now netguard-integrity.timer
sudo rm -f /etc/systemd/system/netguard-integrity.service /etc/systemd/system/netguard-integrity.timer
sudo systemctl daemon-reload
sudo rm -f /usr/local/bin/netguard-lock /usr/local/bin/netguard-integrity /usr/local/bin/netguard-disarm
sudo rm -rf /usr/local/lib/netguard /usr/local/lib/guard /var/lib/netguard
```

## Notas de diseño

- **Golden por ruta completa.** `golden_path` convierte `/etc/hosts` en
  `_etc_hosts`: así dos rutas con el mismo nombre de archivo no colisionan.
- **La lista vive una sola vez** (`files.sh`) y la usan lock e integrity: imposible que se
  desincronicen.
- **Solo se gestiona lo que tiene golden.** `integrity` ignora archivos sin copia de
  referencia: nunca bloquea algo que no puede restaurar.
- **Auto-skip en la restauración.** `netguard-integrity` no se reescribe a sí mismo
  (sobrescribir un script en ejecución corrompe a bash). Sí se re-bloquea con `chattr`,
  que no toca el contenido.
- **Recarga tras restaurar.** Si el archivo restaurado era `nftables.conf`, vuelve a
  cargar las reglas; si era de `resolved` o `/etc/hosts`, limpia la caché de DNS; si era
  de `tmpfiles`, re-aplica los symlinks.
- **`chattr +i` no es un muro.** Es la misma filosofía que el resto del proyecto:
  que apagar el sistema cueste y deje rastro.
