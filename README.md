# dns-doh-lockdown

> A layered, verifiable lockdown that stops browsers and apps from bypassing your DNS
> filter through **DNS-over-HTTPS (DoH)** on Linux.

![Linux](https://img.shields.io/badge/OS-Linux-informational)
![systemd](https://img.shields.io/badge/init-systemd-blue)
![nftables](https://img.shields.io/badge/firewall-nftables-orange)
![DoH](https://img.shields.io/badge/blocks-DNS--over--HTTPS-critical)
![License](https://img.shields.io/badge/license-MIT-green)

> **Status:** building in public, module by module.

## Problem it solves

A DNS filter is trivial to bypass. Turn on DoH in a browser and your queries travel inside
HTTPS — invisible to your resolver. And the obvious fix, blocking DoH by IP, fails too:
Cloudflare, Google and others serve DoH from addresses **shared with thousands of normal
sites**, so an IP blocklist either misses the real endpoints (`cloudflare-dns.com` →
`104.16.x`) or breaks half the web.

This project closes that hole with **five independent layers**, each one covering a
different bypass. No single layer is enough; together, there is no trivial bypass left.

## How it works

| # | Layer | What it does | Module |
|---|-------|--------------|--------|
| 1 | Filtered, encrypted resolver | Resolves through Cloudflare for Families over DoT, no fallback | [`01-resolved-dns`](modules/01-resolved-dns/) |
| 2 | Kernel enforcement | Forces every `:53` to the resolver, blocks DoT/DoH to canonical IPs, covers IPv6, VMs and containers | [`02-firewall-nftables`](modules/02-firewall-nftables/) |
| 3 | DoH kill by name | `/etc/hosts` sinkhole makes DoH endpoint names resolve to loopback | [`03-doh-sinkhole`](modules/03-doh-sinkhole/) |
| 4 | Managed browser policies | `DnsOverHttpsMode: off` across Chromium family and Firefox | [`04-browser-policies`](modules/04-browser-policies/) |
| 5 | Integrity guard | Golden copy + `chattr +i` + a timer that restores and re-locks | [`05-netguard`](modules/05-netguard/) |

The chain in one line: the resolver decides *what* is resolved, the firewall *forces* every
query through it, the policies make browsers *not even try* to bypass it, and the integrity
guard keeps all of it from being silently disabled.

Diagrams: [layers](docs/diagrams/layers.md) · [DNS flow](docs/diagrams/dns-flow.md) ·
[netguard lifecycle](docs/diagrams/netguard-lifecycle.md).

## Quickstart

```bash
git clone https://github.com/ails-w/dns-doh-lockdown.git
cd dns-doh-lockdown
sudo scripts/install.sh --dry-run   # see the plan, change nothing
sudo scripts/install.sh             # install all five modules
sudo scripts/verify.sh              # verify every layer
```

Prefer manual? Each layer is self-contained under [`modules/`](modules/) with its own
apply / verify / rollback README, and can be adopted on its own.

## What I learned / Key decisions

- **DoH cannot be blocked by IP.** Its endpoints live on shared CDNs, so blocking the
  addresses either misses them or breaks unrelated sites. The win is blocking the
  *bootstrap* — the endpoint **name** — before any encrypted packet exists, and letting the
  browser decide not to try (`DnsOverHttpsMode: off`) for the hardcoded-IP case.
- **Use your own nftables tables.** Writing into the shared `filter`/`nat` tables means a
  reload can wipe Docker's or libvirt's rules. Dedicated tables (`dnsguard_*`) make the
  firewall safe to reload — which is what lets the integrity layer re-apply it.
- **Keep integrity separate from user-blocking.** Locking config files and blocking a user
  by schedule are two different lifecycles. Sharing one "disarm" switch would mean editing
  the firewall disables your focus block — a design bug waiting to happen.
- **`chattr +i` is friction, not a boundary.** Root can remove it. The honest promise is
  *deliberate, self-reverting and audited*, not "unbreakable".
- **The verifier lied before the system did.** `scripts/verify.sh` used `set -o pipefail`
  and reported the DNS filter as *failing* — because `resolvectl` exits non-zero **when it
  successfully filters**. The test was wrong, not the system. Lesson: a red check means
  "investigate", not "the thing is broken".

## Known limitations

- **Not a wall against root.** `chattr +i`, timers and logs are friction and audit, not
  enforcement against a privileged user.
- **Hardcoded-IP DoH to an unlisted endpoint** survives every network layer; only the
  browser policy covers that case.
- **Flatpak/Snap browsers** run in a sandbox with their own `/etc` and ignore the policies.
- **Captive portals** (hotel/airport) may fail while the firewall is active.

Full, honest list: [`docs/threat-model.md`](docs/threat-model.md).

## Documentation

| Area | Document |
|------|----------|
| How the modules fit together | [`docs/architecture.md`](docs/architecture.md) |
| What it protects — and what it does not | [`docs/threat-model.md`](docs/threat-model.md) |
| Install order | [`docs/install.md`](docs/install.md) |
| How to verify | [`docs/verification.md`](docs/verification.md) |
| Something broke | [`docs/troubleshooting.md`](docs/troubleshooting.md) |
| Concepts, module by module | [`docs/learning/`](docs/learning/) |
| Diagrams | [`docs/diagrams/`](docs/diagrams/) |

## Repository layout

```text
modules/   one self-contained module per defense layer (files + apply/verify README)
docs/      architecture, threat model, install, verification, learning, diagrams
scripts/   install / uninstall / verify helpers
```

## Roadmap

- [ ] CI: `shellcheck` + `markdownlint` + nftables syntax check on every push
- [ ] `PKGBUILD` for the AUR
- [ ] Deploy notes for non-pacman distros (Debian/Fedora hooks)
- [ ] Export diagrams to SVG/PNG

## License

MIT — see [LICENSE](LICENSE).
