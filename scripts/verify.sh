#!/usr/bin/env bash
# Verifica el estado de dns-doh-lockdown (solo lectura; pide sudo para nft).
# Uso: scripts/verify.sh
set -u

OK=0
FAIL=0

ok()   { printf '  [OK] %s\n' "$1"; OK=$((OK + 1)); }
fail() { printf '  [!!] %s\n' "$1"; FAIL=$((FAIL + 1)); }

echo "== Capa 1: resolver filtrado =="
if resolvectl query example.com >/dev/null 2>&1; then
  ok "resuelve example.com"
else
  fail "no resuelve example.com"
fi
filter_out="$(resolvectl query nudity.testcategory.com 2>&1 || true)"
if printf '%s' "$filter_out" | grep -qiE 'filtered|censored|0\.0\.0\.0'; then
  ok "Cloudflare for Families filtra"
else
  fail "el filtrado no se detecta (¿otro resolver?)"
fi

echo "== Capa 2: firewall =="
if sudo -n true 2>/dev/null; then
  if sudo -n nft list tables 2>/dev/null | grep -q 'dnsguard'; then
    ok "tablas dnsguard_* presentes"
  else
    fail "no se ven tablas dnsguard_*"
  fi
else
  echo "  (sin sudo no interactivo; omite esta capa)"
fi

echo "== Capa 3: sinkhole DoH =="
if resolvectl query cloudflare-dns.com 2>/dev/null | grep -q '127\.0\.0\.1'; then
  ok "cloudflare-dns.com -> 127.0.0.1"
else
  fail "cloudflare-dns.com NO resuelve a loopback (¿ReadEtcHosts?)"
fi

echo "== Capa 4: políticas de navegador =="
if [ -e /etc/browser-policies/chromium-doh-off.json ] &&
   grep -q '"DnsOverHttpsMode": "off"' /etc/browser-policies/chromium-doh-off.json; then
  ok "fuente única Chromium con DoH off"
else
  fail "falta la fuente única de la política Chromium"
fi
if [ -e /etc/brave/policies/managed/00-doh-off.json ]; then
  ok "symlink/política presente en Brave"
else
  echo "  (Brave no detectado; se omite)"
fi

echo "== Capa 5: netguard =="
if lsattr /etc/nftables.conf 2>/dev/null | grep -q '^....i'; then
  ok "/etc/nftables.conf inmutable"
else
  fail "/etc/nftables.conf sin atributo i"
fi
if [ "$(ls -A /var/lib/netguard/golden 2>/dev/null | wc -l)" -gt 0 ]; then
  ok "goldens presentes ($(ls -A /var/lib/netguard/golden | wc -l))"
else
  fail "no hay goldens en /var/lib/netguard/golden"
fi
if systemctl is-active --quiet netguard-integrity.timer; then
  ok "netguard-integrity.timer activo"
else
  fail "netguard-integrity.timer inactivo"
fi

echo
printf 'Resultado: %d OK, %d fallos\n' "$OK" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
