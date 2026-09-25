#!/usr/bin/env bash
# Guard: helpers compartidos (patron golden + inmutable). Se sourcea, no se ejecuta.
GUARD_GOLDEN="${GUARD_GOLDEN:-/var/lib/netguard/golden}"
GUARD_LOG="${GUARD_LOG:-/var/log/netguard/audit.log}"
GUARD_TAG="${GUARD_TAG:-netguard}"

guard_audit() {
  logger -t "$GUARD_TAG" "$1"
  mkdir -p "$(dirname "$GUARD_LOG")" 2>/dev/null || true
  printf "%s %s\n" "$(date -Is)" "$1" >> "$GUARD_LOG" 2>/dev/null || true
}

golden_path() {
  printf "%s/%s" "$GUARD_GOLDEN" "$(printf "%s" "$1" | tr "/" "_")"
}

golden_is_inmutable() {
  lsattr -d "$1" 2>/dev/null | grep -q -- "^....i"
}

golden_lock_one() {
  local live="$1" golden
  [ -e "$live" ] || return 0
  golden="$(golden_path "$live")"
  install -d -m 0755 "$GUARD_GOLDEN"
  chattr -i "$live" 2>/dev/null || true
  cp -a "$live" "$golden"
  chattr +i "$live" "$golden" 2>/dev/null || true
}
