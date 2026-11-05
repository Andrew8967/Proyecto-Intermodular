#!/usr/bin/env bash
# =====================================================================
#  01 — Configuración base y seguridad del servidor
#  Debian 13 (Trixie) x86_64 — ejecutar con: sudo bash 01-setup-base.sh
#
#  Qué hace:
#   1. Actualiza el sistema e instala las herramientas básicas
#   2. Zona horaria y actualizaciones de seguridad automáticas
#   3. Endurece SSH (sin root; sin contraseña SOLO si ya tienes clave)
#   4. Firewall UFW: todo cerrado salvo SSH, web y Minecraft desde la LAN
#   5. fail2ban: bloquea IPs que fallan muchas veces el login por SSH
#  Se puede ejecutar varias veces sin romper nada.
# =====================================================================
source "$(dirname "$0")/lib.sh"
require_root
require_debian
load_config

info "Actualizando el sistema..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get -y upgrade
apt-get install -y \
    curl ca-certificates python3 \
    ufw fail2ban python3-systemd \
    unattended-upgrades \
    htop lm-sensors smartmontools rsync tar gzip

info "Zona horaria: $TIMEZONE"
timedatectl set-timezone "$TIMEZONE"

info "Activando actualizaciones de seguridad automáticas..."
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF

# ---------------------------------------------------------------------
# SSH
# ---------------------------------------------------------------------
info "Configurando SSH..."
apt-get install -y openssh-server
AUTH_KEYS="$(getent passwd "$ADMIN_USER" | cut -d: -f6)/.ssh/authorized_keys"
SSH_CONF=/etc/ssh/sshd_config.d/10-proyecto.conf

{
    echo "# Generado por 01-setup-base.sh"
    echo "PermitRootLogin no"
    echo "MaxAuthTries 3"
    echo "LoginGraceTime 30"
    echo "X11Forwarding no"
    echo "AllowUsers $ADMIN_USER ${EXTRA_SSH_USERS:-}"
    # Solo quitamos las contraseñas si ya hay una clave instalada:
    # si no, te quedarías fuera del servidor.
    if [ -s "$AUTH_KEYS" ]; then
        echo "PasswordAuthentication no"
        echo "KbdInteractiveAuthentication no"
    fi
} > "$SSH_CONF"

if [ -s "$AUTH_KEYS" ]; then
    info "Clave SSH encontrada: login por contraseña DESACTIVADO."
else
    aviso "No hay clave SSH para $ADMIN_USER: se mantiene el login por contraseña."
    aviso "Desde Windows: ssh-keygen -t ed25519  y luego copia la clave (ver docs/05-seguridad.md)."
    aviso "Después vuelve a ejecutar este script para desactivar las contraseñas."
fi
sshd -t || error "La configuración de SSH tiene errores; no reinicio el servicio."
systemctl restart ssh

# ---------------------------------------------------------------------
# Firewall UFW
# ---------------------------------------------------------------------
info "Configurando el firewall UFW (red permitida: $LAN_SUBNET)..."
ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing
ufw allow from "$LAN_SUBNET" to any port 22 proto tcp comment 'SSH (LAN)'
ufw allow from "$LAN_SUBNET" to any port 80 proto tcp comment 'Panel web (LAN)'
ufw allow from "$LAN_SUBNET" to any port 25565 proto tcp comment 'Minecraft (LAN)'
# Solo en la simulación: con NAT de VirtualBox/QEMU el tráfico llega desde 10.0.2.2
if [ "${SIMULACION_NAT:-no}" = "si" ]; then
    aviso "Modo simulación: permito también la red NAT 10.0.2.0/24 (quítalo en el servidor real)."
    ufw allow from 10.0.2.0/24 comment 'NAT de la VM (solo simulacion)'
fi
ufw --force enable
ufw status verbose

# ---------------------------------------------------------------------
# fail2ban
# ---------------------------------------------------------------------
info "Configurando fail2ban para SSH..."
cat > /etc/fail2ban/jail.d/proyecto.local <<EOF
[DEFAULT]
# Debian 13 guarda los logs en journald, no en /var/log/auth.log
backend  = systemd
bantime  = 1h
findtime = 10m
maxretry = 5
# nunca bloquear la propia máquina
ignoreip = 127.0.0.1/8 ::1

[sshd]
enabled = true
EOF
systemctl enable --now fail2ban
systemctl restart fail2ban

# ---------------------------------------------------------------------
# Sensores de temperatura (para el panel)
# ---------------------------------------------------------------------
info "Detectando sensores de temperatura..."
sensors-detect --auto >/dev/null 2>&1 || aviso "sensors-detect no encontró sensores (normal en una VM)."

echo
info "Base lista. Resumen:"
echo "    SSH:       solo usuario '$ADMIN_USER', sin root"
echo "    Firewall:  22, 80 y 25565 abiertos SOLO para $LAN_SUBNET"
echo "    fail2ban:  activo para SSH"
echo
info "Siguiente paso: sudo bash scripts/02-install-papermc.sh"
