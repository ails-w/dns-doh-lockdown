#!/usr/bin/env bash
# Desinstala dns-doh-lockdown (reverso por módulo).
# Uso: sudo scripts/uninstall.sh
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Ejecuta con sudo." >&2
  exit 1
fi

echo "== Módulo 05: netguard =="
systemctl disable --now netguard-integrity.timer 2>/dev/null || true
for f in /etc/nftables.conf /etc/hosts \
         /etc/systemd/resolved.conf.d/00-cloudflare-family.conf \
         /etc/systemd/resolved.conf.d/10-read-etc-hosts.conf \
         /etc/browser-policies/chromium-doh-off.json \
         /etc/browser-policies/firefox-policies.json \
         /etc/tmpfiles.d/browser-doh-lock.conf \
         /etc/pacman.d/hooks/99-browser-doh-lock.hook \
         /usr/local/lib/guard/golden.sh /usr/local/lib/netguard/files.sh \
         /usr/local/bin/netguard-lock /usr/local/bin/netguard-integrity /usr/local/bin/netguard-disarm \
         /etc/systemd/system/netguard-integrity.service /etc/systemd/system/netguard-integrity.timer; do
  chattr -i "$f" 2>/dev/null || true
done
rm -f /etc/systemd/system/netguard-integrity.service /etc/systemd/system/netguard-integrity.timer
rm -f /usr/local/bin/netguard-lock /usr/local/bin/netguard-integrity /usr/local/bin/netguard-disarm
rm -rf /usr/local/lib/netguard /usr/local/lib/guard /var/lib/netguard
systemctl daemon-reload

echo "== Módulo 04: políticas =="
rm -f /etc/tmpfiles.d/browser-doh-lock.conf
rm -f /etc/pacman.d/hooks/99-browser-doh-lock.hook
rm -rf /etc/browser-policies
rm -f /etc/brave/policies/managed/00-doh-off.json
rm -f /etc/chromium/policies/managed/00-doh-off.json
rm -f /etc/opt/chrome/policies/managed/00-doh-off.json
rm -f /etc/opt/edge/policies/managed/00-doh-off.json
rm -f /etc/opt/vivaldi/policies/managed/00-doh-off.json
rm -f /etc/firefox/policies/policies.json

echo "== Módulo 03: sinkhole =="
sed -i '/# BEGIN netguard-doh/,/# END netguard-doh/d' /etc/hosts
resolvectl flush-caches

echo "== Módulo 01: resolved =="
rm -f /etc/systemd/resolved.conf.d/00-cloudflare-family.conf
rm -f /etc/systemd/resolved.conf.d/10-read-etc-hosts.conf
systemctl restart systemd-resolved

echo "== Módulo 02: firewall =="
echo "  (las tablas dnsguard_* quedan en memoria; se borran ahora)"
nft delete table inet dnsguard 2>/dev/null || true
nft delete table ip dnsguard_nat 2>/dev/null || true
nft delete table ip6 dnsguard_nat 2>/dev/null || true
echo "  NOTA: /etc/nftables.conf sigue apuntando a las tablas dnsguard_*."
echo "  Ajustalo o el servicio las recreará en el próximo arranque."

echo
echo "Desinstalado."
