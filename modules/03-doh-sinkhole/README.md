# Módulo 03 — Sinkhole DoH

Mata el *bootstrap* de DoH **por nombre**: hace que los endpoints DoH conocidos resuelvan
a loopback, así el navegador no encuentra a dónde conectarse.

## Prerrequisitos

- `systemd-resolved` con `ReadEtcHosts=yes` (lo aporta el módulo 01).
- root.

## Archivos

| Archivo | Destino | Qué hace |
|---|---|---|
| `files/hosts.doh-block` | se **anexa** a `/etc/hosts` | bloque `netguard-doh` con los nombres DoH → loopback |

## Aplicar

```bash
sudo sh -c 'cat files/hosts.doh-block >> /etc/hosts'
resolvectl flush-caches
```

> El bloque va delimitado por `# BEGIN netguard-doh` / `# END netguard-doh` para poder
> quitarlo limpio después.

## Verificar

```bash
resolvectl query cloudflare-dns.com          # 127.0.0.1 / ::1, "Data from: synthetic"
resolvectl query mozilla.cloudflare-dns.com  # idem
resolvectl query example.com                 # control: IP real
```

Y la prueba real (el endpoint debe quedar inalcanzable):

```bash
curl -sS -o /dev/null -w '%{http_code}\n' \
  -H 'accept: application/dns-json' \
  'https://cloudflare-dns.com/dns-query?name=example.com&type=A'
```

Debe fallar con *connection refused* / `HTTP 000`.

## Rollback

```bash
sudo sed -i '/# BEGIN netguard-doh/,/# END netguard-doh/d' /etc/hosts
resolvectl flush-caches
```

## Por qué se bloquea por nombre (y no por IP)

Los endpoints DoH viven en **CDN compartida**: `cloudflare-dns.com` resuelve a
`104.16.x`, `mozilla.cloudflare-dns.com` a `162.159.x`, y esas mismas IPs sirven miles de
sitios normales. Bloquearlas por IP rompería media internet; bloquear el **nombre** no.

El flujo que se corta es el *bootstrap*: para conectarse al endpoint, el navegador primero
tiene que resolver su nombre con el resolver del sistema. Si ese paso devuelve
`127.0.0.1`, no hay conexión posible.

## Límites

- **No cubre DoH con IP hardcodeada**: una app que traiga la IP grabada no necesita el
  nombre. Ese caso lo cubre la política del módulo 04 (que el software decida no usarlo).
- **Nombres no listados**: un proveedor exótico sobrevive hasta que se agregue su nombre.
- **Efecto colateral**: nombres como `one.one.one.one` (la web de Cloudflare) dejan de
  resolver. Es intencional.
- Ajusta la lista a tu caso; si usas un proveedor DoH legítimo, no lo incluyas.
