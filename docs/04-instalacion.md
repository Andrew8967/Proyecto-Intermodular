# 04 · Instalación paso a paso (Proxmox VE + CT de Minecraft)

Resumen del orden:

```
1. Instalar Proxmox VE 9 en el mini PC         (USB de arranque)
2. bash proxmox/01-postinstall.sh              (en el Proxmox)
3. Montar el disco externo en el Proxmox       (a mano, una vez)
4. bash proxmox/02-crear-ct-minecraft.sh --todo  (crea el CT 101 e instala todo dentro)
5. bash proxmox/03-backups-proxmox.sh          (copias semanales con vzdump)
6. Whitelist de Minecraft y comprobaciones
```

---

## 0. Antes de empezar (BIOS del mini PC)

- **VT-x / Intel Virtualization Technology:** activado.
- **VT-d:** activado (si existe).
- **Restore on AC Power Loss → Power On:** para que el servidor arranque solo si se va la luz.
- **Secure Boot:** desactivado si el USB de Proxmox no arranca.
- Conectar el mini PC al router por **cable Ethernet**.

## 1. Instalar Proxmox VE 9

1. Descargar la ISO de Proxmox VE 9 (proxmox.com → Downloads) y grabarla en un USB con **Rufus** (modo DD) o **balenaEtcher**.
2. Arrancar el mini PC desde el USB → *Install Proxmox VE (Graphical)*.
3. Disco: el **SSD de 128 GB**, con el sistema de archivos `ext4` por defecto (crea `local` y `local-lvm`). ⚠ No elijas el disco externo.
4. País: España; zona horaria: Europe/Madrid; teclado: Spanish.
5. Contraseña de root y un email (el email puede ser inventado).
6. Red:

   | Campo | Valor |
   |---|---|
   | Hostname (FQDN) | `pve.casa.lan` |
   | IP (CIDR) | `192.168.1.10/24` |
   | Gateway | `192.168.1.1` |
   | DNS | `192.168.1.1` |

7. Al terminar, saca el USB. Desde cualquier PC de la red: **`https://192.168.1.10:8006`** → usuario `root`, realm *Linux PAM*. El aviso de "sin suscripción" es normal: Proxmox es gratis.

## 2. Configuración inicial del host

En la web: *pve → Shell* (o por SSH: `ssh root@192.168.1.10`):

```bash
apt update && apt install -y git
git clone https://github.com/Andrew8967/Proyecto-Intermodular.git
cd Proyecto-Intermodular
nano proxmox/proxmox.env        # revisa IPs, recursos del CT y tu usuario
bash proxmox/01-postinstall.sh  # repositorios gratuitos + actualización
reboot                          # si se ha actualizado el kernel
```

> En Proxmox, para actualizar se usa siempre `apt full-upgrade`, nunca `apt upgrade` a secas.

## 3. Montar el disco externo (1-2 TB) en el host

```bash
lsblk -o NAME,SIZE,FSTYPE,LABEL,MODEL     # localiza el disco, por ejemplo /dev/sdb
```

**Disco nuevo o vacío** (⚠ esto lo **borra**: si es de Alberto y tiene datos, hablad antes):

```bash
sgdisk -Z /dev/sdb && sgdisk -n1:0:0 -t1:8300 /dev/sdb
mkfs.ext4 -L externo /dev/sdb1
```

Montaje permanente:

```bash
mkdir -p /mnt/externo
blkid /dev/sdb1                           # copia el UUID
nano /etc/fstab
#   UUID=xxxx-xxxx  /mnt/externo  ext4  defaults,nofail,x-systemd.device-timeout=10s  0  2
systemctl daemon-reload && mount -a && df -h /mnt/externo
mkdir -p /mnt/externo/{ct101,proxmox,alberto}
```

`nofail` permite que Proxmox arranque aunque el disco esté desconectado. Los scripts de copia lo detectan y no escriben en el SSD por error.

## 4. Crear el contenedor de Minecraft (CT 101)

```bash
cd ~/Proyecto-Intermodular
bash proxmox/02-crear-ct-minecraft.sh --todo
```

Este script:
1. Descarga la plantilla `debian-13-standard`.
2. Crea el CT 101 *unprivileged* con *nesting*, 4 núcleos, 8 GB de RAM, 40 GB de disco, IP `192.168.1.100` y arranque automático.
3. Le conecta la carpeta `/mnt/externo/ct101`, que dentro del CT se ve como `/mnt/externo`.
4. Crea tu usuario con `sudo` (te pedirá su contraseña) y descarga el repositorio dentro.
5. Con `--todo`, ejecuta dentro del CT: `01-setup-base` → `02-install-papermc` → `03-install-panel` → `04-setup-backups`.

Sin `--todo`, solo crea el CT. Después puedes instalar paso a paso tú mismo (recomendable la primera vez, para entender cada paso):

```bash
pct enter 101                  # o: ssh andres@192.168.1.100
su - andres
cd ~/Proyecto-Intermodular
sudo bash scripts/01-setup-base.sh
sudo bash scripts/02-install-papermc.sh
sudo bash scripts/03-install-panel.sh
sudo bash scripts/04-setup-backups.sh
bash scripts/estado-servicios.sh
```

Al terminar: **panel en `http://192.168.1.100`** y **Minecraft en `192.168.1.100:25565`**.

## 5. Copias completas con vzdump

```bash
bash proxmox/03-backups-proxmox.sh
```

Registra `/mnt/externo/proxmox` como almacenamiento `externo` y crea una copia **semanal** del CT 101 entero (se ve en *Centro de datos → Copia de seguridad*).

## 6. Minecraft: whitelist y operadores

Dentro del CT 101:

```bash
sudo mc-cmd "whitelist add Andres"
sudo mc-cmd "whitelist add Alberto"
sudo mc-cmd "op Andres"
sudo mc-cmd "list"
journalctl -u minecraft -f          # log en directo (Ctrl+C para salir)
```

Minecraft Java → Multijugador → Añadir servidor → `192.168.1.100`.

## 7. El homelab de Alberto

Alberto crea sus CT o VM con ID **200-299** e IPs **192.168.1.110+** (desde la web: *Crear CT* o *Crear VM*).

**Normas de convivencia** (más importantes que los permisos técnicos):
- Cada uno toca solo sus IDs: 101 es de Andrés, 2xx de Alberto.
- No se cambian los recursos del otro sin avisar.
- Las actualizaciones y reinicios del **host** se hacen de acuerdo entre los dos.

**Usuarios separados (recomendado, y queda muy bien en SOR):**
1. *Centro de datos → Permisos → Usuarios → Añadir*: `andres@pve` y `alberto@pve` (realm *Proxmox VE*).
2. *Centro de datos → Pools → Crear*: `pool-andres` (con el CT 101 dentro) y `pool-alberto`.
3. *Permisos → Añadir → Permiso de usuario*: `/pool/pool-alberto` → `alberto@pve` → rol **PVEAdmin**. Lo mismo para Andrés con su pool.
4. Si Alberto tiene que crear máquinas nuevas, dale también **PVEDatastoreUser** sobre `/storage/local-lvm` y `/storage/local`.

Así cada uno entra en la web con su usuario y solo ve y gestiona lo suyo. `root` queda para administrar el host.

Su carpeta en el disco externo, `/mnt/externo/alberto`, se le conecta a su CT igual que en el paso 4: `pct set <id> -mp0 /mnt/externo/alberto,mp=/mnt/datos`.

## 8. Actualizar más adelante

```bash
# Host Proxmox
apt update && apt full-upgrade

# Dentro del CT 101
cd ~/Proyecto-Intermodular && git pull
sudo bash scripts/03-install-panel.sh          # web y recolector nuevos
# Nueva versión de Minecraft: cambia PAPER_VERSION en scripts/config.env y:
sudo backup-minecraft && sudo bash scripts/02-install-papermc.sh
```

> Antes de cualquier cambio grande: **snapshot del CT 101** desde la web (Instantáneas → Tomar instantánea). Si algo sale mal, se vuelve atrás en segundos.

---

## Problemas típicos

| Síntoma | Qué mirar |
|---|---|
| `apt update` da error 401 en el Proxmox | No se ha ejecutado `proxmox/01-postinstall.sh` (repositorio enterprise activo) |
| El CT no tiene Internet | ¿`GATEWAY` y `CT_IP` son correctos? `pct config 101`, y dentro `ip a` y `ping 1.1.1.1` |
| UFW no se activa dentro del CT | Usa el firewall de Proxmox para el CT ([05-seguridad.md](05-seguridad.md)) |
| `$'\r': command not found` | Finales de línea de Windows: clona con git o ejecuta `sed -i 's/\r$//' scripts/*.sh proxmox/*.sh` |
| El panel dice "SIN CONEXIÓN" | Dentro del CT: `systemctl status panel-status` y `journalctl -u panel-status -n 30` |
| Temperatura "N/D" en el panel | El CT no ve `/sys/class/hwmon`. Comprueba en el host que `sensors` muestra datos |
| Minecraft no arranca | `journalctl -u minecraft -n 50`. ¿RAM suficiente en el CT? ¿Versión de Java correcta? |
| No conecto a Minecraft desde otro PC | `sudo ufw status` en el CT, y que `LAN_SUBNET` sea tu red |
| Error de permisos en `/mnt/externo` dentro del CT | En el host: `chown 100000:100000 /mnt/externo/ct101` |
