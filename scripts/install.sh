#!/usr/bin/env bash
# Instala todos los módulos de dns-doh-lockdown.
# Uso: sudo scripts/install.sh [--dry-run]
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=1
fi

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    printf '[dry-run] %s\n' "$*"
  else
    "$@"
  fi
}

if [ "$(id -u)" -ne 0 ]; then
  echo "Ejecuta con sudo." >&2
  exit 1
fi

echo "== Módulo 01: resolved =="
run install -d /etc/systemd/resolved.conf.d
run cp "$REPO_DIR/modules/01-resolved-dns/files/00-cloudflare-family.conf" \
       "$REPO_DIR/modules/01-resolved-dns/files/10-read-etc-hosts.conf" \
       /etc/systemd/resolved.conf.d/
run systemctl restart systemd-resolved

echo "== Módulo 02: firewall =="
run cp "$REPO_DIR/modules/02-firewall-nftables/files/nftables.conf" /etc/nftables.conf
if [ "$DRY_RUN" -eq 0 ]; then
  nft -c -f /etc/nftables.conf
fi
run systemctl enable --now nftables.service
run systemctl restart nftables.service

echo "== Módulo 03: sinkhole =="
if grep -q 'BEGIN netguard-doh' /etc/hosts; then
  echo "  (ya presente, se omite)"
else
  run sh -c "cat '$REPO_DIR/modules/03-doh-sinkhole/files/hosts.doh-block' >> /etc/hosts"
fi
run resolvectl flush-caches

echo "== Módulo 04: políticas de navegador =="
run install -d /etc/browser-policies
run cp "$REPO_DIR/modules/04-browser-policies/files/chromium-doh-off.json" \
       "$REPO_DIR/modules/04-browser-policies/files/firefox-policies.json" \
       /etc/browser-policies/
run cp "$REPO_DIR/modules/04-browser-policies/files/browser-doh-lock.conf" /etc/tmpfiles.d/
run install -d /etc/pacman.d/hooks
run cp "$REPO_DIR/modules/04-browser-policies/files/99-browser-doh-lock.hook" /etc/pacman.d/hooks/
run systemd-tmpfiles --create /etc/tmpfiles.d/browser-doh-lock.conf

echo "== Módulo 05: netguard =="
run install -d /usr/local/lib/guard /usr/local/lib/netguard
run install -m 0644 "$REPO_DIR/modules/05-netguard/files/lib/guard/golden.sh" /usr/local/lib/guard/golden.sh
run install -m 0644 "$REPO_DIR/modules/05-netguard/files/lib/netguard/files.sh" /usr/local/lib/netguard/files.sh
for f in "$REPO_DIR"/modules/05-netguard/files/bin/netguard-*; do
  run install -m 0755 "$f" /usr/local/bin/
done
run install -m 0644 "$REPO_DIR/modules/05-netguard/files/units/netguard-integrity.service" \
                    "$REPO_DIR/modules/05-netguard/files/units/netguard-integrity.timer" \
                    /etc/systemd/system/
run systemctl daemon-reload
run systemctl enable --now netguard-integrity.timer
run netguard-lock

echo
echo "Instalado. Verifica con: sudo scripts/verify.sh"
