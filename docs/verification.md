# Verificación

Cómo comprobar que cada capa hace lo que dice. Ejecuta las pruebas **en orden**: si una
falla, no sigas.

> Automatización: `scripts/verify.sh` (pendiente) reproduce esta batería.

## Capa 1 — Resolver filtrado

```bash
resolvectl status
resolvectl query example.com          # IP real, "Data from: network"
resolvectl query nudity.testcategory.com   # bloqueado por Families (Filtered/Censored)
```

**Esperado:** el resolver es `1.1.1.3`, la consulta normal resuelve y el dominio de prueba
resulta **bloqueado**. (Cloudflare Families responde `0.0.0.0` a dominios filtrados, y
como esa respuesta no está firmada, `resolvectl` la reporta como *Filtered/Censored*:
eso es la prueba de que filtra.)

## Capa 2 — Firewall

```bash
sudo nft list tables | grep dnsguard
sudo nft list ruleset | grep -A3 'table inet dnsguard'

# DNS forzado: no debe salir nada que no sea 1.1.1.3 / 1.0.0.3
sudo tcpdump -ni wlan0 'port 53 and not host 1.1.1.3 and not host 1.0.0.3'

# DoT permitido solo a Families
timeout 5 bash -c 'echo | openssl s_client -connect 1.1.1.3:853 -servername cloudflare-dns.com'   # OK
timeout 5 bash -c 'echo | openssl s_client -connect 9.9.9.9:853 -servername dns.quad9.net'       # timeout
```

**Esperado:** las tablas `dnsguard_*` existen, el `tcpdump` no imprime nada, y DoT solo
funciona contra `1.1.1.3`.

## Capa 3 — Sinkhole DoH

```bash
resolvectl query cloudflare-dns.com          # 127.0.0.1 / ::1, "Data from: synthetic"
resolvectl query mozilla.cloudflare-dns.com  # idem
resolvectl query example.com                 # control: IP real, NO 127.0.0.1
```

Y la prueba real de que el endpoint murió:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' \
  -H 'accept: application/dns-json' \
  'https://cloudflare-dns.com/dns-query?name=example.com&type=A'
```

**Esperado:** falla con *connection refused* / `HTTP 000`.

## Capa 4 — Políticas de navegador

```bash
readlink -f /etc/brave/policies/managed/00-doh-off.json
cat /etc/browser-policies/chromium-doh-off.json
```

**Esperado:** el symlink apunta a la fuente única y el contenido es `"DnsOverHttpsMode": "off"`.
En el navegador: `brave://policy` (o `chrome://policy`) muestra la política como *Managed*.

## Capa 5 — netguard

```bash
lsattr /etc/nftables.conf /etc/hosts /etc/browser-policies/*.json
ls -A /var/lib/netguard/golden/ | wc -l
```

**Esperado:** todos con el atributo `i`, y tantos goldens como archivos protegidos.

Prueba de reversión (sabotaje controlado):

```bash
sudo chattr -i /etc/hosts
sudo sh -c 'echo "# sabotage" >> /etc/hosts'
sudo systemctl start netguard-integrity.service
tail -3 /etc/hosts      # "# sabotage" debe haber desaparecido
lsattr /etc/hosts       # debe volver a tener 'i'
sudo journalctl -t netguard -n 5 --no-pager
```

## Persistencia (reinicio)

El test definitivo: todo debe **reaparecer solo** tras un reboot.

```bash
sudo reboot
```

Después de arrancar:

```bash
sudo nft list tables | grep dnsguard
ls -l /etc/brave/policies/managed/00-doh-off.json
lsattr /etc/hosts /etc/nftables.conf
systemctl is-active netguard-integrity.timer
resolvectl query cloudflare-dns.com
```

## Checklist final

- [ ] Capa 1: filtrado activo y consultas normales resolviendo.
- [ ] Capa 2: tablas presentes, sin fuga de DNS, DoT restringido.
- [ ] Capa 3: nombres DoH → loopback; endpoint DoH inalcanzable.
- [ ] Capa 4: política visible como *Managed* en el navegador.
- [ ] Capa 5: archivos inmutables + reversión automática funcionando.
- [ ] Persistencia: todo sobrevive al reboot.
