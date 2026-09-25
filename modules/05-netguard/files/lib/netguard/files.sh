#!/usr/bin/env bash
# netguard: lista unica de archivos protegidos.
NG_FILES=(
	/etc/nftables.conf
	/etc/hosts
	/etc/systemd/resolved.conf.d/00-cloudflare-family.conf
	/etc/systemd/resolved.conf.d/10-read-etc-hosts.conf
	/etc/browser-policies/chromium-doh-off.json
	/etc/browser-policies/firefox-policies.json
	/etc/tmpfiles.d/browser-doh-lock.conf
	/etc/pacman.d/hooks/99-browser-doh-lock.hook
	/usr/local/lib/guard/golden.sh
	/usr/local/lib/netguard/files.sh
	/usr/local/bin/netguard-lock
	/usr/local/bin/netguard-integrity
	/usr/local/bin/netguard-disarm
	/etc/systemd/system/netguard-integrity.service
	/etc/systemd/system/netguard-integrity.timer
	# Agrega aqui tus propios archivos a proteger, por ejemplo:
	# /etc/brave/policies/managed/seguridad.json
)
