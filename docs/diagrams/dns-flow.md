# Flujo DNS

Una consulta normal y el *bootstrap* de DoH, lado a lado.

```mermaid
sequenceDiagram
    participant App
    participant NSS as glibc / NSS
    participant R as systemd-resolved (127.0.0.53)
    participant H as /etc/hosts
    participant CF as 1.1.1.3 (DoT)

    Note over App,CF: Consulta normal
    App->>NSS: getaddrinfo("example.com")
    NSS->>R: consulta
    R->>H: ¿está en /etc/hosts?
    H-->>R: no
    R->>CF: consulta cifrada (853)
    CF-->>R: IP real
    R-->>NSS: IP real
    NSS-->>App: IP real

    Note over App,CF: Bootstrap de DoH
    App->>NSS: getaddrinfo("cloudflare-dns.com")
    NSS->>R: consulta
    R->>H: ¿está en /etc/hosts?
    H-->>R: 127.0.0.1 (synthetic)
    R-->>NSS: 127.0.0.1
    NSS-->>App: 127.0.0.1
    App--xApp: no hay servidor DoH en loopback → DoH muere
```

Lectura: el sinkhole actúa **antes** de que exista cualquier paquete cifrado. No hay que
"ganarle" a TLS: se corta el paso previo.
