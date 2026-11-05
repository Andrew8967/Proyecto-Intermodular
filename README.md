# Servidor Personal en Mini PC x86 con Proxmox VE — Proyecto Intermodular

**Alumno:** Andrés David Olarte Molina  
**Curso:** 2º SMR — I.E.S. Ribera del Tajo  
**Año:** 2026/2027  
**Colaboración:** homelab compartido con Alberto en el mismo equipo

---

## Descripción

Servidor personal de bajo coste (**~150 €**) basado en un **mini PC x86_64 con 16 GB de RAM** y **Proxmox VE 9** como sistema base. Funciona 24 horas al día en la red local (LAN). Cada proyecto va en su propio contenedor, aislado:

```
Mini PC — Proxmox VE 9 (192.168.1.10:8006)
├── CT 101 mc-server (Debian 13, LXC) · 192.168.1.100 → Minecraft + panel  [Andrés]
├── CT/VM 2xx · 192.168.1.110+                        → homelab           [Alberto]
└── Disco externo 1-2 TB                              → copias + datos
```

Servicios:

| Servicio | Software | Puerto | Estado |
|---|---|---|---|
| 🎮 **Servidor de Minecraft** (principal) | PaperMC (Java Edition) + Java 21 | 25565 | Script listo · pendiente de probar en la VM |
| 📊 **Panel de monitorización** | Apache2 + HTML/CSS/JS + recolector en Python | 80 | Funcional con datos de ejemplo · pendiente en la VM |
| 💾 **Copias de seguridad** | Mundo cada noche (tar) + CT entero cada semana (vzdump) → disco externo | — | Scripts listos |
| 🖥️ **Virtualización** | Proxmox VE 9: CT LXC sin privilegios, snapshots, vzdump | 8006 | Scripts listos · pendiente de probar |
| 🖧 **Homelab de Alberto** | Su propio CT/VM en el mismo Proxmox | — | Pendiente de hardware |
| 🤖 Chatbot de IA local *(extra opcional)* | Ollama + Open WebUI | 3000 | Opcional |

El panel muestra **en tiempo real**: jugadores conectados (con sus nombres), TPS, MSPT, ping, estado del servidor con historial de caídas, CPU, RAM, temperatura y espacio en disco.

**Ver el panel con datos de ejemplo:** descarga la carpeta [`panel-web/`](panel-web/) y abre `index.html` en el navegador (se activa solo el **modo demo**).

---

## Por qué un mini PC x86 y no una Raspberry Pi 5

La primera versión usaba una Raspberry Pi 5 ([documentación v1](docs/archivo/documentacion-v1-raspberry-pi5.pdf)). Se cambió porque:

- **La simulación es idéntica al servidor real.** El portátil y el mini PC son x86_64, así que la VM de pruebas usa los mismos paquetes y los mismos scripts. ARM solo se puede emular, y va muy lento.
- **Más potencia por núcleo y el doble de RAM** (16 GB), sin comprar accesorios aparte.
- **Proxmox VE** (solo existe oficialmente para x86_64): compartimos el equipo con Alberto sin que un proyecto afecte al otro, con snapshots y copias completas.
- **Más barato:** ~150 € todo incluido, frente a ~207-300 € de la Pi 5 con accesorios.

Detalles y checklist de compra: [docs/01-hardware.md](docs/01-hardware.md).

---

## Cómo funciona el panel

```
                    cada 10 s                          cada 5 s
 PaperMC ──RCON + Server List Ping──► panel-status.py ──► status.json ◄──fetch()── navegador
 /proc, /sys (CPU, RAM, temperatura, discos) ──┘                 (Apache2)
```

Una web estática no puede leer el estado del sistema por sí sola. El recolector [`panel-status.py`](scripts/panel/panel-status.py) (Python, sin librerías externas) hace de puente: consulta Minecraft y el sistema y escribe un JSON que la página lee y pinta.

---

## Hardware previsto

| Componente | Detalle | Precio aprox. |
|---|---|---|
| Mini PC | x86_64 (i3 / Intel N-series), 16 GB RAM, SSD 128 GB, Ethernet | ~150 € |
| Disco externo | 1-2 TB USB 3.0 (aportado) — copias + homelab de Alberto | 0 € |
| Cable Ethernet | Cat 6 | reutilizado |
| **Total** | | **~150 €** |

> El modelo exacto se elegirá en AliExpress o Temu. Requisitos mínimos en [docs/01-hardware.md](docs/01-hardware.md).

---

## Instalación rápida

1. Instalar **Proxmox VE 9** en el mini PC (IP `192.168.1.10`).
2. En la consola del Proxmox, como root:

```bash
apt update && apt install -y git
git clone https://github.com/Andrew8967/Proyecto-Intermodular.git
cd Proyecto-Intermodular
nano proxmox/proxmox.env                       # IPs, recursos del CT, tu usuario

bash proxmox/01-postinstall.sh                 # repositorios gratuitos + actualización
#   (montar el disco externo en /mnt/externo: docs/04-instalacion.md, paso 3)
bash proxmox/02-crear-ct-minecraft.sh --todo   # crea el CT 101 e instala todo dentro
bash proxmox/03-backups-proxmox.sh             # copia semanal del CT con vzdump
```

3. Panel en `http://192.168.1.100` · Minecraft en `192.168.1.100:25565`.

Dentro del CT, `--todo` ejecuta `scripts/01` (seguridad) → `02` (PaperMC) → `03` (panel) → `04` (copias). También se pueden lanzar a mano, uno a uno.

Guía completa: [docs/04-instalacion.md](docs/04-instalacion.md).

---

## Documentación

| Documento | Contenido |
|---|---|
| [01 · Hardware](docs/01-hardware.md) | Cambio desde la Raspberry Pi, requisitos, checklist de compra, presupuesto, BIOS |
| [02 · Arquitectura](docs/02-arquitectura.md) | Esquema de red, Proxmox y CT 101, por qué LXC, puertos, reparto con Alberto |
| [03 · Simulación](docs/03-simulacion.md) | Prueba A (servicios en VM Debian 13) y prueba B (Proxmox en VirtualBox) |
| [04 · Instalación](docs/04-instalacion.md) | BIOS, Proxmox, disco externo, CT 101, vzdump, usuarios de Alberto, problemas típicos |
| [05 · Seguridad](docs/05-seguridad.md) | UFW y firewall de Proxmox, SSH, fail2ban, Tailscale, copias, vzdump, snapshots |
| [06 · Planificación](docs/06-planificacion.md) | Fases, estado, plan de pruebas, módulos y ODS |

---

## Estado actual

- [x] Propuesta de idea y cambio de Raspberry Pi 5 a mini PC x86
- [x] Entorno de simulación: VM con Debian 13 y Apache2
- [x] Primera versión del panel web desplegada en la VM
- [x] Scripts v2: seguridad base, PaperMC, panel en vivo, copias de seguridad
- [x] Panel con datos reales (`status.json`) y modo demo
- [x] Proxmox VE como base: scripts de postinstalación, CT 101 y vzdump
- [ ] Prueba A: scripts de servicios en una VM Debian 13
- [ ] Prueba B: Proxmox en VirtualBox creando el CT 101
- [ ] Comprar el mini PC (~150 €)
- [ ] Instalar Proxmox en el mini PC, desplegar el CT 101 y el homelab de Alberto
- [ ] Pruebas de rendimiento y seguridad, memoria final

---

## Módulos integrados

| Módulo | Aplicación |
|---|---|
| Sistemas Operativos Monopuestos | Debian en terminal, systemctl, usuarios y permisos |
| Redes de Área Local | LAN, IP fija o reserva DHCP, puertos, modelo OSI |
| Montaje y Mantenimiento de Equipos | Elección del mini PC, BIOS, discos, consumo |
| Aplicaciones Web | Panel HTML5/CSS3/JS con `fetch()` y JSON |
| Sistemas Operativos en Red | Proxmox VE: contenedores LXC, recursos, usuarios y permisos, snapshots |
| Seguridad Informática | UFW y firewall de Proxmox, CT sin privilegios, SSH con clave, fail2ban, copias |
| Servicios en Red | Apache2, PaperMC, RCON, gestión de puertos |

---

## Estructura del repositorio

```
├── README.md
├── docs/                         documentación del proyecto
│   ├── 01-hardware.md … 06-planificacion.md
│   └── archivo/                  versión 1 (Raspberry Pi 5), como histórico
├── proxmox/                      se ejecuta en el HOST Proxmox (como root)
│   ├── proxmox.env               configuración del host y del CT 101
│   ├── 01-postinstall.sh         repositorios gratuitos + actualización
│   ├── 02-crear-ct-minecraft.sh  crea el CT 101 (--todo instala todo dentro)
│   └── 03-backups-proxmox.sh     copia semanal del CT con vzdump
├── panel-web/                    panel de monitorización (Apache2)
│   ├── index.html
│   ├── style.css
│   └── script.js
└── scripts/                      se ejecuta DENTRO del CT 101 (Debian 13)
    ├── config.env                configuración de los servicios
    ├── lib.sh                    funciones compartidas
    ├── 01-setup-base.sh          sistema, SSH, UFW, fail2ban
    ├── 02-install-papermc.sh     servidor de Minecraft
    ├── 03-install-panel.sh       Apache2 + recolector + comando mc-cmd
    ├── 04-setup-backups.sh       copias de seguridad automáticas
    ├── estado-servicios.sh       resumen rápido del servidor
    ├── extra-install-ollama.sh   (opcional) chatbot de IA local
    └── panel/panel-status.py     recolector de datos del panel
```

---

> Proyecto en desarrollo activo. Los scripts están escritos para Proxmox VE 9 y Debian 13 (x86_64). Se probarán primero en VirtualBox y después en el mini PC. La optimización de recursos queda para una fase posterior.
