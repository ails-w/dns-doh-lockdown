# Módulo 04 — Políticas de navegador

Hace que los navegadores **ni lo intenten**: una política gestionada desactiva DoH en toda
la familia Chromium y en Firefox, desplegada desde una **fuente única** con symlinks y
re-aplicada automáticamente cuando se instala o actualiza cualquier navegador.

Esta es la capa que cubre lo que la red **no puede**: un DoH contra una IP hardcodeada no
genera un nombre que envenenar ni una IP que no rompa media internet. Si el software
decide no usar DoH, no hay paquete que bloquear.

## Prerrequisitos

- `systemd` (para `systemd-tmpfiles`, que re-aplica en cada arranque).
- Arch Linux: hook de `pacman` (o el equivalente de tu distro).

## Archivos

| Archivo | Destino | Qué hace |
|---|---|---|
| `files/chromium-doh-off.json` | `/etc/browser-policies/` | fuente única Chromium (`DnsOverHttpsMode: off`) |
| `files/firefox-policies.json` | `/etc/browser-policies/` | fuente única Firefox (`DNSOverHTTPS: off`, locked) |
| `files/browser-doh-lock.conf` | `/etc/tmpfiles.d/` | crea symlinks hacia la fuente única |
| `files/99-browser-doh-lock.hook` | `/etc/pacman.d/hooks/` | re-aplica tras cualquier transacción de pacman |

## Aplicar

```bash
sudo install -d /etc/browser-policies
sudo cp files/chromium-doh-off.json files/firefox-policies.json /etc/browser-policies/
sudo cp files/browser-doh-lock.conf /etc/tmpfiles.d/
sudo install -d /etc/pacman.d/hooks
sudo cp files/99-browser-doh-lock.hook /etc/pacman.d/hooks/
sudo systemd-tmpfiles --create /etc/tmpfiles.d/browser-doh-lock.conf
```

## Verificar

```bash
ls -l /etc/brave/policies/managed/00-doh-off.json
readlink -f /etc/brave/policies/managed/00-doh-off.json
```

En el navegador: `brave://policy` (o `chrome://policy`) debe mostrar `DnsOverHttpsMode`
como **`off`** y **Managed**.

## Rollback

```bash
sudo systemd-tmpfiles --remove /etc/tmpfiles.d/browser-doh-lock.conf
sudo rm -f /etc/tmpfiles.d/browser-doh-lock.conf
sudo rm -f /etc/pacman.d/hooks/99-browser-doh-lock.hook
sudo rm -rf /etc/browser-policies
```

## Notas de diseño

- **Fuente única + symlinks.** El contenido real vive en `/etc/browser-policies/`; cada
  navegador ve un enlace. Actualizas una vez y todos la ven. Además, un candado de
  integridad (módulo 05) sobre la fuente protege a todos los enlaces de golpe.
- **`managed/` es obligatorio, no sugerido.** Chromium lee `policies/managed/` como
  políticas *mandatorias*: el usuario no puede cambiarlas desde la UI.
- **Formatos distintos.** Chromium: `{"DnsOverHttpsMode": "off"}`. Firefox: un único
  `policies.json` con `{"policies": {"DNSOverHTTPS": {...}}}` (`Enabled: false` →
  `network.trr.mode = 5`; `Locked: true` impide el cambio en `about:config`).
- **Una sola clave por fuente.** No repitas `DnsOverHttpsMode` en otros archivos de la
  misma carpeta `managed/`: el orden de fusión no está garantizado.
- **El hook usa `Target = *`.** Se dispara en cualquier instalación/actualización de
  cualquier paquete, así un navegador nuevo queda cubierto sin intervención.
- **Fuera de Arch:** reemplaza el hook de pacman por el de tu gestor, o ejecuta
  `systemd-tmpfiles --create` tras instalar. Los symlinks igual se regeneran en cada
  arranque (systemd aplica `/etc/tmpfiles.d/` en el boot).
- **Vivaldi** lee `/etc/chromium/policies` en algunas versiones y `/etc/opt/vivaldi` en
  otras: el config cubre **ambas**. **Opera** no soporta políticas de Chromium de forma
  fiable y queda fuera.
- **Flatpak/Snap:** no leen las políticas del host (sandbox con su propio `/etc`).
