# Ciclo de netguard

Estados de la protección y las transiciones permitidas.

```mermaid
stateDiagram-v2
    [*] --> Bloqueado: netguard-lock
    Bloqueado --> ConDrift: edición sin desarmar
    ConDrift --> Bloqueado: integrity restaura (≤ 1 min)
    Bloqueado --> Desbloqueado: netguard-disarm<br/>(sudo + frase + 60 s)
    Desbloqueado --> Bloqueado: editar + netguard-lock
    Desbloqueado --> [*]: timers detenidos
```

Detalle de la transición de desarme:

```mermaid
sequenceDiagram
    participant U as Usuario (root)
    participant NG as netguard-disarm
    participant T as netguard-integrity.timer

    U->>NG: sudo netguard-disarm
    NG->>U: pide frase "desarmar red"
    U->>NG: frase correcta
    NG->>NG: espera 60 s (Ctrl+C aborta)
    NG->>T: systemctl stop
    NG->>NG: chattr -i (todos los archivos)
    NG->>NG: guarda en audit.log
```

Lectura: no hay forma de "saltarse" el desarme sin hacer exactamente lo que hace
`netguard-disarm` (o algo más destructivo y evidente). Así, cada desactivación es
deliberada, lenta y auditada.
