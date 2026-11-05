#!/usr/bin/env bash
# =====================================================================
#  P2 — Crea el contenedor LXC de Minecraft (CT 101, Debian 13)
#  Ejecutar EN EL PROXMOX como root:
#     bash proxmox/02-crear-ct-minecraft.sh             (solo crea el CT)
#     bash proxmox/02-crear-ct-minecraft.sh --todo      (crea el CT e instala TODO dentro)
#
#  Qué hace:
#   1. Descarga la plantilla oficial debian-13-standard
#   2. Crea el CT sin privilegios (unprivileged) con "nesting" (lo necesita
#      systemd para aislar servicios) y arranque automático
#   3. Si el disco externo está montado, le da una carpeta propia
#      (en el CT se ve como /mnt/externo: ahí van las copias del mundo)
#   4. Crea tu usuario con sudo dentro del CT y descarga este repositorio
#   5. Con --todo, ejecuta dentro los scripts 01 a 04 de scripts/
#
#  ¿Por qué un contenedor y no una VM?
#   - Comparte el kernel del host: menos RAM y CPU desperdiciadas
#   - Puede leer los sensores de temperatura del host (una VM no)
#   - Arranca en segundos y se puede hacer snapshot igual que una VM
# =====================================================================
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/proxmox.env"

info()  { echo -e "\033[0;32m[+]\033[0m $*"; }
aviso() { echo -e "\033[0;33m[!]\033[0m $*"; }
error() { echo -e "\033[0;31m[x]\033[0m $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || error "Ejecútalo como root en el Proxmox."
command -v pct >/dev/null || error "Esto no es un Proxmox VE (no encuentro pct)."
INSTALAR_TODO=no
[ "${1:-}" = "--todo" ] && INSTALAR_TODO=si

if pct status "$CTID" >/dev/null 2>&1; then
    aviso "El CT $CTID ya existe: no lo creo de nuevo."
else
    # -----------------------------------------------------------------
    # Plantilla
    # -----------------------------------------------------------------
    info "Buscando la plantilla debian-13-standard..."
    pveam update >/dev/null
    TEMPLATE="$(pveam available --section system | awk '/debian-13-standard/ {print $2}' | sort -V | tail -1)"
    [ -n "$TEMPLATE" ] || error "No encuentro la plantilla debian-13-standard (pveam available --section system)."
    if ! pveam list "$TEMPLATE_STORAGE" | grep -q "$TEMPLATE"; then
        info "Descargando $TEMPLATE..."
        pveam download "$TEMPLATE_STORAGE" "$TEMPLATE"
    fi

    # -----------------------------------------------------------------
    # Crear el contenedor
    # -----------------------------------------------------------------
    info "Creando CT $CTID ($CT_HOSTNAME, $CT_IP)..."
    EXTRA_ARGS=()
    [ -n "$SSH_PUBKEY_FILE" ] && [ -f "$SSH_PUBKEY_FILE" ] && EXTRA_ARGS+=(--ssh-public-keys "$SSH_PUBKEY_FILE")
    pct create "$CTID" "$TEMPLATE_STORAGE:vztmpl/$TEMPLATE" \
        --hostname "$CT_HOSTNAME" \
        --ostype debian \
        --unprivileged 1 \
        --features nesting=1 \
        --cores "$CT_CORES" \
        --memory "$CT_MEMORY" \
        --swap "$CT_SWAP" \
        --rootfs "$CT_STORAGE:$CT_DISK_GB" \
        --net0 "name=eth0,bridge=$BRIDGE,ip=$CT_IP/${LAN_SUBNET#*/},gw=$GATEWAY,firewall=1" \
        --nameserver "$DNS" \
        --timezone host \
        --onboot 1 \
        --startup order=1 \
        --description "Minecraft (PaperMC) + panel de monitorización — Andrés" \
        "${EXTRA_ARGS[@]}"
fi

# ---------------------------------------------------------------------
# Disco externo: carpeta propia para el CT
# ---------------------------------------------------------------------
if mountpoint -q "$EXTERNAL_MOUNT"; then
    if ! pct config "$CTID" | grep -q "mp=/mnt/externo"; then
        info "Dando al CT la carpeta $CT_BACKUP_HOST_DIR del disco externo..."
        mkdir -p "$CT_BACKUP_HOST_DIR"
        # En un CT sin privilegios, el root de dentro es el usuario 100000 de fuera
        chown 100000:100000 "$CT_BACKUP_HOST_DIR"
        pct stop "$CTID" >/dev/null 2>&1 || true
        pct set "$CTID" -mp0 "$CT_BACKUP_HOST_DIR,mp=/mnt/externo,backup=0"
    fi
else
    aviso "El disco externo no está montado en $EXTERNAL_MOUNT: el CT se crea sin él."
    aviso "Cuando lo montes, vuelve a ejecutar este script para conectarlo."
fi

info "Arrancando CT $CTID..."
pct start "$CTID" 2>/dev/null || true
for _ in $(seq 1 30); do
    pct exec "$CTID" -- true 2>/dev/null && break
    sleep 1
done
# esperar a que tenga red
for _ in $(seq 1 30); do
    pct exec "$CTID" -- getent hosts deb.debian.org >/dev/null 2>&1 && break
    sleep 2
done

# ---------------------------------------------------------------------
# Preparar el CT por dentro
# ---------------------------------------------------------------------
info "Preparando el CT: sudo, git, usuario $ADMIN_USER y repositorio..."
pct exec "$CTID" -- bash -c "
    set -e
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -q
    apt-get install -y -q sudo git locales
    sed -i 's/^# *es_ES.UTF-8/es_ES.UTF-8/' /etc/locale.gen && locale-gen >/dev/null
    if ! id '$ADMIN_USER' >/dev/null 2>&1; then
        adduser --disabled-password --gecos '' '$ADMIN_USER'
    fi
    usermod -aG sudo '$ADMIN_USER'
    if [ -s /root/.ssh/authorized_keys ]; then
        install -d -m 700 -o '$ADMIN_USER' -g '$ADMIN_USER' /home/$ADMIN_USER/.ssh
        install -m 600 -o '$ADMIN_USER' -g '$ADMIN_USER' /root/.ssh/authorized_keys /home/$ADMIN_USER/.ssh/authorized_keys
    fi
    cd /home/$ADMIN_USER
    if [ -d Proyecto-Intermodular/.git ]; then
        sudo -u '$ADMIN_USER' git -C Proyecto-Intermodular pull -q
    else
        sudo -u '$ADMIN_USER' git clone -q '$REPO_URL'
    fi
    cfg=Proyecto-Intermodular/scripts/config.env
    sed -i 's|^ADMIN_USER=.*|ADMIN_USER=\"$ADMIN_USER\"|;
            s|^SERVER_IP=.*|SERVER_IP=\"$CT_IP\"|;
            s|^LAN_SUBNET=.*|LAN_SUBNET=\"$LAN_SUBNET\"|;
            s|^GATEWAY=.*|GATEWAY=\"$GATEWAY\"|' \$cfg
"

if ! pct exec "$CTID" -- bash -c "getent shadow '$ADMIN_USER' | cut -d: -f2 | grep -qv '^[!*]'"; then
    echo
    info "Pon una contraseña al usuario $ADMIN_USER del CT (la pedirá sudo):"
    pct exec "$CTID" -- passwd "$ADMIN_USER"
fi

if [ "$INSTALAR_TODO" = "si" ]; then
    info "Instalando todo dentro del CT (01 a 04)..."
    for s in 01-setup-base.sh 02-install-papermc.sh 03-install-panel.sh 04-setup-backups.sh; do
        info "=== $s ==="
        pct exec "$CTID" -- bash "/home/$ADMIN_USER/Proyecto-Intermodular/scripts/$s"
    done
fi

echo
info "CT $CTID listo."
echo "    Entrar desde Proxmox:     pct enter $CTID"
echo "    Entrar por SSH:           ssh $ADMIN_USER@$CT_IP"
if [ "$INSTALAR_TODO" = "si" ]; then
    echo "    Panel:                    http://$CT_IP/"
    echo "    Minecraft:                $CT_IP:25565"
else
    echo "    Instalar los servicios (dentro del CT):"
    echo "        cd ~/Proyecto-Intermodular && sudo bash scripts/01-setup-base.sh   (y luego 02, 03 y 04)"
    echo "    o, desde el Proxmox, todo de una vez:  bash proxmox/02-crear-ct-minecraft.sh --todo"
fi
echo
info "Siguiente paso (en el Proxmox): bash proxmox/03-backups-proxmox.sh"
