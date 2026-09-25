# dns-doh-lockdown

A layered, verifiable lockdown that stops browsers and apps from bypassing your DNS
filter through **DNS-over-HTTPS (DoH)** on Linux.

> **Status:** work in progress — building in public, module by module.

## Why

DNS filtering is trivial to bypass. A browser with DoH enabled resolves names over
HTTPS, invisible to your resolver, and blocking DoH by IP address fails too:
Cloudflare, Google and others serve DoH from shared CDN addresses, so an IP
blocklist either misses the real endpoints or breaks half the web.

This project layers five independent defenses so that no single bypass works:

| # | Layer | Module |
|---|-------|--------|
| 1 | Filtered, encrypted OS resolver (systemd-resolved + DoT) | `modules/01-resolved-dns` |
| 2 | Kernel enforcement (nftables: forced DNS, DoT/DoH blocks, IPv6) | `modules/02-firewall-nftables` |
| 3 | DoH kill by name (`/etc/hosts` sinkhole) | `modules/03-doh-sinkhole` |
| 4 | Managed browser policies (Chromium family + Firefox) | `modules/04-browser-policies` |
| 5 | Tamper-evident integrity guard (golden copy + `chattr +i`) | `modules/05-netguard` |

Each module is self-contained and can be adopted on its own. Together they form a
single chain: the resolver decides *what* is resolved, the firewall *forces* every
query through it, the browser policies make browsers *not even try* to bypass it,
and the integrity guard keeps all of it from being silently disabled.

## Documentation

| Area | Document |
|------|----------|
| How the modules fit together | `docs/architecture.md` |
| What it protects (and what it does not) | `docs/threat-model.md` |
| Install order | `docs/install.md` |
| How to verify | `docs/verification.md` |
| Something broke | `docs/troubleshooting.md` |
| Concepts, module by module | `docs/learning/` |
| Diagrams | `docs/diagrams/` |

## Repository layout

```text
modules/   one self-contained module per defense layer (files + apply/verify README)
docs/      architecture, threat model, install, verification, learning, diagrams
scripts/   install / uninstall / verify helpers
```

## License

MIT — see [LICENSE](LICENSE).
