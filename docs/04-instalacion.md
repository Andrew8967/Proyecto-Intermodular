# 04 · Instalación paso a paso

Sirve igual para la máquina virtual de pruebas y para el mini PC real (o para el contenedor de Proxmox).

## 1. Instalar Debian 13 "Trixie"

Durante el instalador:
- **Contraseña de root: déjala VACÍA.** Así Debian instala `sudo` y da permisos de administrador a tu usuario, que es lo que esperan los scripts.
- Usuario normal: por ejemplo `andres`.
- Disco: "Guiado - utilizar todo el disco".
- Programas: solo **servidor SSH** y **utilidades estándar del sistema**. Sin entorno de escritorio.

> **Con Proxmox (opción A):** se instala Proxmox VE en el mini PC y se crea un contenedor LXC con la plantilla *debian-13-standard* (unprivileged, con **nesting activado**, 4 núcleos, 8 GB de RAM y 40 GB de disco). Dentro del contenedor se sigue desde el paso 2.

## 2. IP fija

El servidor tiene que tener siempre la misma IP para que los jugadores lo encuentren.

**Forma recomendada: reserva DHCP en el router.** En la web del router (normalmente `192.168.1.1`) → DHCP → reserva estática: asocia la MAC del mini PC a `192.168.1.100`. No hay que tocar nada en Debian.

**Forma alternativa: IP estática en Debian.** Mira el nombre de la interfaz con `ip a` (por ejemplo `enp1s0`) y edita `/etc/network/interfaces`:

```
auto enp1s0
iface enp1s0 inet static
    address 192.168.1.100/24
    gateway 192.168.1.1
    dns-nameservers 192.168.1.1 1.1.1.1
```

Después, `sudo systemctl restart networking`. Hazlo con teclado y pantalla conectados, no por SSH: si te equivocas, pierdes la conexión.

## 3. Descargar el proyecto

```bash
sudo apt install -y git
git clone https://github.com/Andrew8967/Proyecto-Intermodular.git
cd Proyecto-Intermodular
nano scripts/config.env      # revisa ADMIN_USER, SERVER_IP, LAN_SUBNET...
```

## 4. Ejecutar los scripts en orden

```bash
sudo bash scripts/01-setup-base.sh        # actualizaciones, SSH, firewall, fail2ban
sudo bash scripts/02-install-papermc.sh   # Java + PaperMC como servicio
sudo bash scripts/03-install-panel.sh     # Apache2 + panel + recolector de datos
sudo bash scripts/04-setup-backups.sh     # copias nocturnas al disco externo
bash scripts/estado-servicios.sh          # comprobar que todo está activo
```

Todos los scripts se pueden volver a ejecutar sin romper nada (por ejemplo, después de cambiar `config.env`).

## 5. Minecraft: whitelist y operadores

Con `MC_WHITELIST="true"` solo entran los jugadores que añadas:

```bash
sudo mc-cmd "whitelist add Andres"
sudo mc-cmd "whitelist add Alberto"
sudo mc-cmd "op Andres"              # administrador dentro del juego
sudo mc-cmd "list"                   # quién está conectado
journalctl -u minecraft -f           # log en directo (Ctrl+C para salir)
```

Para conectar: Minecraft Java → Multijugador → Añadir servidor → `192.168.1.100`.

## 6. Disco externo (1-2 TB)

```bash
lsblk -f                          # localiza el disco, por ejemplo /dev/sdb1
sudo mkfs.ext4 -L externo /dev/sdb1    # ⚠ BORRA el disco. Solo si está vacío o es nuevo
sudo mkdir -p /mnt/externo
sudo blkid /dev/sdb1              # copia el UUID
```

Añade a `/etc/fstab` (con el UUID que te salga):

```
UUID=xxxx-xxxx  /mnt/externo  ext4  defaults,nofail,x-systemd.device-timeout=10s  0  2
```

```bash
sudo mount -a && df -h /mnt/externo
```

`nofail` hace que el servidor arranque aunque el disco esté desconectado. El script de copias detecta que no está montado y no copia nada, para no llenar el SSD.

> Si el disco lo compartís con Alberto, no lo formatees sin hablarlo: podéis hacer dos particiones, o usar carpetas separadas (`/mnt/externo/backups` y `/mnt/externo/alberto`).

## 7. Actualizar el servidor más adelante

```bash
cd ~/Proyecto-Intermodular && git pull
sudo bash scripts/03-install-panel.sh     # copia la web nueva y reinicia el recolector
# Nueva versión de Minecraft: cambia PAPER_VERSION en config.env, haz una copia y:
sudo backup-minecraft && sudo bash scripts/02-install-papermc.sh
```

## Problemas típicos

| Síntoma | Qué mirar |
|---|---|
| `$'\r': command not found` | El script tiene finales de línea de Windows. Clona con git (el `.gitattributes` lo evita) o ejecuta `sed -i 's/\r$//' scripts/*.sh` |
| El panel dice "SIN CONEXIÓN" | `systemctl status panel-status` y `journalctl -u panel-status -n 30` |
| Minecraft no arranca | `journalctl -u minecraft -n 50`. ¿Hay RAM suficiente? ¿La versión de Java es la correcta? |
| No conecto desde otro PC | `sudo ufw status` (¿está bien `LAN_SUBNET`?), `ss -tln \| grep 25565` |
| El panel no muestra TPS | RCON desactivado: revisa `enable-rcon=true` en `/opt/minecraft/server.properties` |
