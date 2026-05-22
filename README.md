# Servidor Personal en Raspberry Pi 5 — Proyecto Intermodular

**Alumno:** Andrés David Olarte Molina  
**Curso:** 1º SMR — I.E.S. Ribera del Tajo  
**Año:** 2025/2026

---

## Descripción

Diseño, simulación y documentación de un servidor personal multifunción basado en una **Raspberry Pi 5 de 8GB RAM**. El servidor opera en red local (LAN) y contempla tres servicios:

| Servicio | Software | Puerto | Estado |
|---|---|---|---|
| Servidor Web | Apache2 + HTML/CSS/JS | 80 | [✓] Funcional en simulación |
| Servidor Minecraft | PaperMC Java Edition | 25565 | [en proceso] Documentado, pendiente de hardware |
| Chatbot IA Local | Ollama + Open WebUI | 3000 | [en proceso] Documentado, pendiente de hardware |

El desarrollo inicial se realiza sobre **QEMU + Debian 13** como entorno de simulación, equivalente funcional de Raspberry Pi OS al compartir el mismo kernel Linux y gestor de paquetes apt.

---

## Estado actual

- [x] Propuesta y boceto inicial del proyecto
- [x] Investigación de hardware y justificación de componentes
- [x] Configuración del entorno de simulación QEMU
- [x] Instalación de Debian 13 en máquina virtual
- [x] Configuración de red LAN, IP estática y SSH
- [x] Configuración del firewall UFW y puertos
- [x] Despliegue de Apache2 y página web propia
- [x] Scripts de instalación preparados para todos los servicios
- [ ] Despliegue del servidor Minecraft (pendiente hardware)
- [ ] Despliegue del chatbot IA local (pendiente hardware)
- [ ] Implementación en Raspberry Pi 5 física

---

## Módulos integrados

| Módulo | Aplicación |
|---|---|
| Sistemas Operativos Monopuestos | Administración de Linux en terminal, systemctl, usuarios, permisos |
| Redes de Área Local | LAN, IP estática, modelo OSI, firewall UFW, SSH, puertos |
| Montaje y Mantenimiento de Equipos | Selección y justificación del hardware |
| Aplicaciones Web | Desarrollo y despliegue de web propia con HTML/CSS/JS |

---

## Hardware previsto

| Componente | Modelo | Precio aprox. |
|---|---|---|
| SBC | Raspberry Pi 5 — 8GB | ~90€ |
| SSD | NVMe 512GB M.2 2242 | ~60€ |
| HAT NVMe | Adaptador PCIe para Pi 5 | ~15€ |
| Refrigeración | Disipador activo oficial | ~10€ |
| Fuente | USB-C 27W oficial | ~12€ |
| Carcasa + cables | — | ~20€ |
| **Total** | | **~207€ — 300€** |

---

## Estructura del repositorio

```
proyecto-intermodular/
├── README.md
├── docs/
│   ├── 01-introduccion.md
│   ├── 02-hardware.md
│   ├── 03-simulacion-qemu.md
│   ├── 04-so-configuracion.md
│   ├── 05-redes.md
│   ├── 06-minecraft.md
│   ├── 07-servidor-web.md
│   ├── 08-chatbot-local.md
│   └── 09-temporalizacion.md
├── src/
│   └── web/
│       ├── index.html
│       ├── style.css
│       └── script.js
├── config/
│   ├── server.properties
│   ├── ufw-rules.md
│   └── apache-vhost.conf
└── scripts/
    ├── install-papermc.sh
    ├── install-ollama.sh
    └── start-services.sh
```

---

## Entorno de simulación

- **Host:** Windows 11 — Intel i7-1255U — 16GB RAM
- **Emulador:** QEMU 11.0.0
- **SO virtual:** Debian 13 Bookworm (amd64)
- **Puertos redirigidos:** 2222→22 (SSH), 8080→80 (web), 25565→25565 (Minecraft), 3000→3000 (chatbot)

---

> Este repositorio está en desarrollo activo. Los servicios documentados pero no desplegados se implementarán en el hardware real en fases posteriores del proyecto.
