# 03 · Entorno de simulación (antes de tener el mini PC)

**Equipo de desarrollo:** Windows 11 Home, Intel i7-1255U, 16 GB de RAM.

Hay dos cosas que probar, y conviene hacerlas en este orden:

| | Qué se prueba | Dónde |
|---|---|---|
| **A** | Los servicios: los scripts `scripts/01` a `04` (Minecraft, panel, seguridad, copias) | VM con **Debian 13** (lo mismo que hay dentro del CT 101) |
| **B** | Proxmox: instalación, crear el CT con `proxmox/02`, snapshots, vzdump | VM con **Proxmox VE 9** |

Proxmox 9 está construido sobre Debian 13 y el CT 101 también es Debian 13, así que lo que funciona en la prueba A funciona igual dentro del contenedor.

Para las dos pruebas se usa **VirtualBox** (gratis, funciona en Windows 11 Home). VMware Workstation Pro también es gratis para uso personal y sirve igual.

---

## Prueba A: VM con Debian 13

1. Descargar la ISO **Debian 13 "Trixie" netinst amd64** de debian.org.
2. Nueva VM: 2 CPU, 4 GB de RAM y disco de 30 GB.
3. Instalar con la **contraseña de root vacía** (así tu usuario tiene `sudo`), y marcar solo *servidor SSH* y *utilidades estándar*.
4. Red **NAT** con reenvío de puertos (Configuración → Red → Avanzadas):

   | Nombre | Anfitrión | Invitado |
   |---|---|---|
   | ssh | 2222 | 22 |
   | web | 8080 | 80 |
   | minecraft | 25565 | 25565 |

5. Dentro de la VM:
   ```bash
   sudo apt install -y git
   git clone https://github.com/Andrew8967/Proyecto-Intermodular.git
   cd Proyecto-Intermodular
   nano scripts/config.env      # SIMULACION_NAT="si"   (y LAN_SUBNET da igual en NAT)
   sudo bash scripts/01-setup-base.sh
   sudo bash scripts/02-install-papermc.sh
   sudo bash scripts/03-install-panel.sh
   ```
6. Desde Windows: `ssh -p 2222 usuario@localhost`, el panel en `http://localhost:8080` y Minecraft en `localhost:25565`.

> `SIMULACION_NAT="si"` hace falta porque en modo NAT todo el tráfico llega a la VM desde `10.0.2.2`. En el servidor real se deja en `"no"`.

---

## Prueba B: VM con Proxmox VE 9

Los **contenedores LXC no necesitan virtualización anidada**, así que el CT 101 funciona dentro de un Proxmox virtualizado sin problema. Lo que va lento o no funciona son las VM *dentro* de ese Proxmox, y para este proyecto no hacen falta.

1. Descargar la ISO de **Proxmox VE 9** de proxmox.com (Downloads).
2. Nueva VM en VirtualBox: tipo *Linux / Debian 64-bit*, 2-4 CPU, **4 GB de RAM**, disco de **64 GB**.
3. **Red: Adaptador puente** (*Bridged*), con **Modo promiscuo: Permitir todo**. El CT tiene su propia MAC y necesita que la red la deje pasar.
   - ⚠ **Con WiFi el puente suele fallar para el CT**: el portátil no deja pasar otra MAC por la WiFi. Si te pasa, conecta el portátil por **cable** o haz la prueba A, que no tiene este problema.
4. Instalar Proxmox (ver [04-instalacion.md](04-instalacion.md), paso 1). Usa una IP libre de tu red de casa.
5. Desde Windows, abre `https://IP-del-proxmox:8006` (acepta el aviso del certificado) y entra con `root`.
6. En la consola del Proxmox (*Shell* en la web):
   ```bash
   apt install -y git
   git clone https://github.com/Andrew8967/Proyecto-Intermodular.git
   cd Proyecto-Intermodular
   nano proxmox/proxmox.env           # CT_IP, GATEWAY y LAN_SUBNET de tu red de casa
   bash proxmox/01-postinstall.sh
   bash proxmox/02-crear-ct-minecraft.sh --todo
   ```
7. Practica lo importante para la memoria:
   - **Snapshot:** CT 101 → Instantáneas → Tomar instantánea, rompe algo a propósito y vuelve atrás.
   - **Copia y restauración** con vzdump ([05-seguridad.md](05-seguridad.md)).
   - Disco externo simulado: añade un **segundo disco virtual** de 20 GB a la VM de Proxmox y móntalo en `/mnt/externo`.

---

## Qué se puede probar y qué no

| En simulación | Solo en el mini PC real |
|---|---|
| Todos los scripts (`proxmox/` y `scripts/`) | Temperaturas reales en el panel |
| Minecraft conectándose desde el portátil | Rendimiento real (TPS con varios jugadores) |
| Panel con datos en vivo | Consumo eléctrico |
| UFW, SSH con clave, fail2ban | Disco externo USB real |
| Snapshots, vzdump y restauración | Arranque automático tras un corte de luz |
| CT del homelab de Alberto (pequeño) | Reparto real de RAM y CPU entre los dos |
