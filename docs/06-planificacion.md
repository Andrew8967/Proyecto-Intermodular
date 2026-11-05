# 06 · Planificación, estado y pruebas

## Fases (8 semanas)

```mermaid
gantt
    dateFormat  YYYY-MM-DD
    axisFormat  S%W
    section Entorno base
    Scripts v2 y panel en vivo      :active, b2, 2026-11-05, 7d
    Compra del mini PC              :b3, 2026-11-06, 14d
    section Servicios
    Red, SSH, UFW, fail2ban en la VM :c1, 2026-11-12, 7d
    Minecraft + panel en la VM      :c2, after c1, 7d
    Despliegue en el mini PC        :c3, after b3, 7d
    Homelab de Alberto / Proxmox    :c4, after b3, 10d
    section Cierre
    Pruebas, capturas y memoria     :d1, after c3, 7d
```

> Ya completado antes: investigación del hardware, cambio a x86 y VM Debian 13 con Apache2. Las fechas son orientativas. La compra depende del envío de AliExpress o Temu (1-3 semanas).

## Estado actual

- [x] Propuesta de idea y cambio de Raspberry Pi 5 a mini PC x86
- [x] VM Debian 13 con Apache2 y la primera versión del panel
- [x] Scripts v2: base y seguridad, PaperMC, panel, copias
- [x] Panel con datos en vivo (`status.json`) y modo demo
- [ ] Probar los scripts v2 en la VM
- [ ] Comprar el mini PC (presupuesto ~150 €)
- [ ] Desplegar en el hardware real
- [ ] Homelab de Alberto
- [ ] Pruebas de rendimiento y memoria final

## Plan de pruebas

Cada prueba con su captura de pantalla, para la memoria.

| # | Prueba | Cómo | Resultado esperado |
|---|---|---|---|
| 1 | Servicios activos tras reiniciar | `sudo reboot` → `bash scripts/estado-servicios.sh` | Todo `active` sin tocar nada |
| 2 | Conexión al servidor de Minecraft | Desde otro PC de la LAN | Entra; un jugador fuera de la whitelist **no** entra |
| 3 | Panel en vivo | Abrir `http://IP` desde el móvil | Se ven jugadores, TPS, RAM y CPU actualizándose |
| 4 | Detección de caídas | `sudo systemctl stop minecraft` | El panel pone APAGADO y añade un evento en el historial |
| 5 | Rendimiento | 3-5 jugadores explorando 15 min | TPS ≥ 19,5 y MSPT < 50 ms |
| 6 | Firewall | `nmap 192.168.1.100` desde otro equipo | Solo 22, 80 y 25565 abiertos |
| 7 | fail2ban | 5 logins SSH fallidos | La IP queda bloqueada |
| 8 | Copia y restauración | `sudo backup-minecraft` y restaurar ([05-seguridad.md](05-seguridad.md)) | El mundo vuelve al estado de la copia |
| 9 | Corte de luz | Desenchufar y enchufar | Arranca solo (BIOS) y vuelven todos los servicios |
| 10 | Consumo | Enchufe medidor, en reposo y con carga | Dato en W y coste al mes |

## Módulos de 1º y 2º de SMR

| Módulo | Curso | Qué se aplica | Enfoque |
|---|---|---|---|
| Sistemas Operativos Monopuestos | 1º | Instalación de Debian, terminal, systemctl, usuarios y permisos | Práctico |
| Redes de Área Local | 1º | LAN, IP fija o reserva DHCP, puertos TCP, modelo OSI | Teórico/práctico |
| Montaje y Mantenimiento de Equipos | 1º | Elección del mini PC, BIOS, discos, consumo | Teórico/práctico |
| Aplicaciones Web | 1º | Panel HTML5/CSS3/JS que consume JSON con `fetch()` | Práctico |
| Sistemas Operativos en Red | 2º | Servidor Linux en red, servicios systemd, Proxmox, usuarios compartidos | Práctico |
| Seguridad Informática | 2º | UFW, SSH con clave, fail2ban, mínimo privilegio, copias 3-2-1 | Teórico/práctico |
| Servicios en Red | 2º | Apache2, PaperMC, RCON, gestión de puertos | Práctico |

## Relación con los ODS

**ODS 9 (Industria, innovación e infraestructura):** una infraestructura propia, de bajo coste (~150 €), con software libre (Debian, Apache2, PaperMC, Proxmox), sin depender de servicios de pago en la nube. Además, el equipo lo comparten dos personas, lo que aprovecha mejor el hardware.
