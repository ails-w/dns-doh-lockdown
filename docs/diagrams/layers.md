# Capas

Cómo las cinco capas cubren vectores distintos y ninguna alcanza sola.

```mermaid
flowchart TD
    APP["App / navegador"]

    subgraph L1["1 · Resolver (módulo 01)"]
        RES["systemd-resolved<br/>filtra (Families) + cifra (DoT)"]
    end
    subgraph L2["2 · Firewall (módulo 02)"]
        FW["nftables dnsguard_*<br/>fuerza :53 · corta DoT/DoH a IPs canónicas"]
    end
    subgraph L3["3 · Sinkhole (módulo 03)"]
        SNK["/etc/hosts<br/>nombres de endpoints DoH → loopback"]
    end
    subgraph L4["4 · Políticas (módulo 04)"]
        POL["DnsOverHttpsMode: off<br/>Chromium + Firefox"]
    end
    subgraph L5["5 · Integridad (módulo 05)"]
        NG["golden + chattr +i<br/>restaura y re-bloquea"]
    end

    APP -->|"resolución normal"| RES
    APP -.->|"DNS hardcodeado (8.8.8.8:53)"| FW
    APP -.->|"DoT a terceros (9.9.9.9:853)"| FW
    APP -.->|"DoH por nombre"| SNK
    APP -.->|"DoH por IP fija"| POL

    NG -.->|"protege"| RES
    NG -.->|"protege"| FW
    NG -.->|"protege"| SNK
    NG -.->|"protege"| POL
```

Lectura: cada flecha punteada es un intento de bypass; la capa a la que llega es la que lo
detiene. La capa 5 no detiene tráfico: protege a las otras cuatro de ser desactivadas.
