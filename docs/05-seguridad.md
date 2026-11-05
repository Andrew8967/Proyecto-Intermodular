# 05 · Seguridad y copias de seguridad (SEIN)

Lo que se aplica, por capas:

| Capa | Medida | Dónde se configura |
|---|---|---|
| Red | Sin puertos abiertos en el router: el servidor no es accesible desde Internet | Router |
| Virtualización | Minecraft en un **CT sin privilegios**: aunque alguien lograra ser root dentro, en el host no es nadie (usuario 100000). El homelab de Alberto está aislado en su propio CT/VM | `proxmox/02-crear-ct-minecraft.sh` |
| Gestión | Web de Proxmox (8006) solo accesible desde la LAN, con usuarios separados por persona y permisos por pool | Proxmox ([04-instalacion.md](04-instalacion.md), paso 7) |
| Firewall | UFW dentro del CT: denegar todo lo entrante; permitir 22, 80 y 25565 **solo desde la LAN** | `01-setup-base.sh` |
| Acceso remoto | SSH sin root, solo usuarios permitidos, con **clave** y sin contraseña | `01-setup-base.sh` |
| Fuerza bruta | fail2ban: 5 intentos fallidos en 10 min → IP bloqueada 1 hora | `01-setup-base.sh` |
| Servicios | Minecraft y el recolector usan un usuario sin login (`minecraft`) y sandbox de systemd | `02` y `03` |
| Minecraft | `online-mode=true` (cuentas oficiales) + **whitelist**; RCON con contraseña aleatoria de 24 caracteres y bloqueado por UFW desde fuera | `02-install-papermc.sh` |
| Web | Apache sin listado de carpetas y sin mostrar su versión (`ServerTokens Prod`) | `03-install-panel.sh` |
| Integridad | El `.jar` de Paper se verifica con **SHA-256** antes de instalarlo | `02-install-papermc.sh` |
| Parches | `unattended-upgrades`: actualizaciones de seguridad automáticas | `01-setup-base.sh` |
| Datos | Copia diaria del mundo (7 días de historial) + copia **semanal del CT entero** con vzdump, las dos en el disco externo | `04-setup-backups.sh` y `proxmox/03-backups-proxmox.sh` |
| Cambios | **Snapshot** del CT antes de cada cambio importante: se vuelve atrás en segundos | Web de Proxmox |

## Si UFW no funciona dentro del CT: firewall de Proxmox

En algunos contenedores UFW no puede activarse. El script `01-setup-base.sh` lo detecta y avisa. En ese caso, las mismas reglas se ponen desde Proxmox, que filtra el tráfico **antes** de que llegue al CT (el script `02-crear-ct-minecraft.sh` ya deja el CT preparado con `firewall=1` en su tarjeta de red):

1. *Centro de datos → Cortafuegos → Opciones → Cortafuegos: Sí*. Proxmox permite por defecto el acceso a 8006 y 22 desde la red local, así que no te quedas fuera.
2. *CT 101 → Cortafuegos → Añadir*, una regla por línea:

   | Dirección | Acción | Origen | Protocolo | Puerto destino | Comentario |
   |---|---|---|---|---|---|
   | in | ACCEPT | 192.168.1.0/24 | tcp | 22 | SSH |
   | in | ACCEPT | 192.168.1.0/24 | tcp | 80 | Panel |
   | in | ACCEPT | 192.168.1.0/24 | tcp | 25565 | Minecraft |

3. *CT 101 → Cortafuegos → Opciones*: **Cortafuegos: Sí** y **Política de entrada: DROP**.

> Usar los dos (Proxmox y UFW) tampoco es malo: es **defensa en profundidad**.

## SSH con clave desde Windows

En PowerShell (en tu PC):

```powershell
ssh-keygen -t ed25519                     # Enter a todo, o ponle una frase de paso
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh andres@192.168.1.100 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
ssh andres@192.168.1.100                  # ya no te pide la contraseña del servidor
```

Después vuelve a ejecutar `sudo bash scripts/01-setup-base.sh`. Al detectar la clave, **desactiva el login por contraseña**.

## Comprobaciones para la memoria (capturas)

```bash
sudo ufw status numbered                  # reglas del firewall
sudo fail2ban-client status sshd          # IPs bloqueadas
sudo sshd -T | grep -E 'permitrootlogin|passwordauthentication'
ss -tuln                                  # puertos escuchando (25575 escucha, pero UFW no lo deja pasar)
curl -I http://localhost                  # cabecera "Server: Apache" sin versión
```

**Prueba de ataque controlado** (en tu propia red): desde otro equipo, falla la contraseña de SSH 5 veces y comprueba que fail2ban bloquea la IP. Desbloquear: `sudo fail2ban-client set sshd unbanip <IP>`.

## Jugar desde fuera de casa (sin abrir puertos)

**No** se redirige el 25565 en el router: expondría el servidor a todo Internet. En su lugar se usa **Tailscale**, una VPN gratuita basada en WireGuard.

Se instala en el **host Proxmox**, no en el CT: un CT sin privilegios no tiene el dispositivo `tun` que necesita la VPN. El host hace de "router" hacia el CT:

```bash
# en el Proxmox
curl -fsSL https://tailscale.com/install.sh -o tailscale.sh && sh tailscale.sh
echo 'net.ipv4.ip_forward = 1' > /etc/sysctl.d/99-tailscale.conf && sysctl -p /etc/sysctl.d/99-tailscale.conf
tailscale up --advertise-routes=192.168.1.100/32
```

Después, en la web de Tailscale, aprueba la ruta. Cada amigo instala Tailscale, se une a tu red (o le compartes el equipo) y se conecta a `192.168.1.100:25565` como si estuviera en casa. Solo llega a Minecraft y al panel, no al resto de la red.

## Copias de seguridad

- **Automática:** cada noche a las 04:00 (`systemctl list-timers minecraft-backup.timer`).
- **Manual:** `sudo backup-minecraft`.
- Antes de copiar, el script hace `save-off` y `save-all flush` (guarda el mundo y pausa el autoguardado), y al terminar comprueba que el `.tar.gz` se puede leer.
- Se guardan las 7 últimas en `/mnt/externo/backups/minecraft/`.

### Restaurar una copia (¡practícalo al menos una vez!)

```bash
sudo systemctl stop minecraft
cd /opt/minecraft
sudo mv world world.roto-$(date +%F)          # no borres nada hasta comprobar
sudo tar -xzf /mnt/externo/backups/minecraft/mundo-AAAA-MM-DD_HHMM.tar.gz -C /opt/minecraft
sudo chown -R minecraft:minecraft /opt/minecraft
sudo systemctl start minecraft
```

### Copia completa del CT (vzdump) y cómo restaurarla

- Automática: cada domingo a las 03:00, se guardan las 4 últimas (*Centro de datos → Copia de seguridad*).
- Manual, en el Proxmox: `vzdump 101 --storage externo --mode snapshot --compress zstd`.

Restaurar, desde la web: *externo → Copias de seguridad →* elige la copia → **Restaurar**. Si pones otro ID (por ejemplo 901) tienes una copia al lado para comprobarla sin tocar el original. Por consola:

```bash
pct stop 101
pct restore 101 /mnt/externo/proxmox/dump/vzdump-lxc-101-AAAA_MM_DD-HH_MM_SS.tar.zst --storage local-lvm --force
pct start 101
```

### Snapshots (no son copias de seguridad)

Un **snapshot** congela el estado del CT en el mismo SSD. Sirve para deshacer un cambio en segundos (*CT 101 → Instantáneas → Revertir*), pero **si el SSD muere, el snapshot muere con él**. Por eso hacen falta las copias en el disco externo.

> Una copia que nunca se ha restaurado no es una copia: es una esperanza. Documenta en la memoria una restauración real, con capturas.

**Regla 3-2-1** (para mencionarla): 3 copias de los datos, en 2 soportes distintos, 1 fuera de casa. Aquí se cumple el "2" (SSD + disco externo, con dos niveles: mundo diario y CT semanal). Para el "1", se puede copiar de vez en cuando el último `.tar.gz` a un pendrive o a la nube.
