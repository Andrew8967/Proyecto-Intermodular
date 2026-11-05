# 05 · Seguridad y copias de seguridad (SEIN)

Lo que se aplica, por capas:

| Capa | Medida | Dónde se configura |
|---|---|---|
| Red | Sin puertos abiertos en el router: el servidor no es accesible desde Internet | Router |
| Firewall | UFW: denegar todo lo entrante; permitir 22, 80 y 25565 **solo desde la LAN** | `01-setup-base.sh` |
| Acceso remoto | SSH sin root, solo usuarios permitidos, con **clave** y sin contraseña | `01-setup-base.sh` |
| Fuerza bruta | fail2ban: 5 intentos fallidos en 10 min → IP bloqueada 1 hora | `01-setup-base.sh` |
| Servicios | Minecraft y el recolector usan un usuario sin login (`minecraft`) y sandbox de systemd | `02` y `03` |
| Minecraft | `online-mode=true` (cuentas oficiales) + **whitelist**; RCON con contraseña aleatoria de 24 caracteres y bloqueado por UFW desde fuera | `02-install-papermc.sh` |
| Web | Apache sin listado de carpetas y sin mostrar su versión (`ServerTokens Prod`) | `03-install-panel.sh` |
| Integridad | El `.jar` de Paper se verifica con **SHA-256** antes de instalarlo | `02-install-papermc.sh` |
| Parches | `unattended-upgrades`: actualizaciones de seguridad automáticas | `01-setup-base.sh` |
| Datos | Copia diaria del mundo al disco externo, con 7 días de historial | `04-setup-backups.sh` |

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

**No** se redirige el 25565 en el router: expondría el servidor a todo Internet. En su lugar se usa **Tailscale**, una VPN gratuita basada en WireGuard:

```bash
curl -fsSL https://tailscale.com/install.sh -o tailscale.sh && sudo sh tailscale.sh
sudo tailscale up
```

Cada amigo instala Tailscale, se une a tu red y se conecta a la IP `100.x.y.z` del servidor. Hay que permitir esa red en UFW: `sudo ufw allow in on tailscale0`.

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

> Una copia que nunca se ha restaurado no es una copia: es una esperanza. Documenta en la memoria una restauración real, con capturas.

**Regla 3-2-1** (para mencionarla): 3 copias de los datos, en 2 soportes distintos, 1 fuera de casa. Aquí se cumple el "2" (SSD + disco externo). Para el "1", se puede copiar de vez en cuando el último `.tar.gz` a un pendrive o a la nube.
