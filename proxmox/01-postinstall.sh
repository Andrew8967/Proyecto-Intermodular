#!/usr/bin/env bash
# =====================================================================
#  P1 — Configuración inicial del host Proxmox VE 9 (base Debian 13)
#  Ejecutar EN EL PROXMOX como root:  bash proxmox/01-postinstall.sh
#
#  Qué hace:
#   1. Desactiva los repositorios "enterprise" (son de pago y dan error
#      401 en "apt update" sin suscripción)
#   2. Activa el repositorio gratuito "pve-no-subscription"
#   3. Actualiza Proxmox (en Proxmox siempre "full-upgrade", nunca "upgrade")
#   4. Instala herramientas útiles (sensores, git, smartctl)
#   5. Comprueba que la CPU tiene virtualización activada (VT-x)
#  Se puede ejecutar varias veces.
# =====================================================================
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/proxmox.env"

info()  { echo -e "\033[0;32m[+]\033[0m $*"; }
aviso() { echo -e "\033[0;33m[!]\033[0m $*"; }
error() { echo -e "\033[0;31m[x]\033[0m $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || error "Ejecútalo como root en el Proxmox."
command -v pveversion >/dev/null || error "Esto no es un Proxmox VE (no encuentro pveversion)."
pveversion

CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")"   # trixie en Proxmox 9
info "Base Debian: $CODENAME"

# ---------------------------------------------------------------------
# Repositorios
# ---------------------------------------------------------------------
info "Desactivando repositorios enterprise..."
SL=/etc/apt/sources.list.d
for f in "$SL/pve-enterprise.sources" "$SL/ceph.sources"; do
    # Proxmox 9 usa archivos .sources (formato deb822)
    if [ -f "$f" ] && ! grep -q '^Enabled: false' "$f"; then
        echo "Enabled: false" >> "$f"
        echo "    desactivado $f"
    fi
done
for f in "$SL/pve-enterprise.list" "$SL/ceph.list"; do
    # Proxmox 8 y anteriores usaban archivos .list
    [ -f "$f" ] && sed -i 's/^deb /# deb /' "$f" && echo "    desactivado $f"
done

info "Activando el repositorio gratuito pve-no-subscription..."
if [ -f "$SL/pve-enterprise.sources" ] || [ "$CODENAME" = "trixie" ]; then
    cat > "$SL/proxmox.sources" <<EOF
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: $CODENAME
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
EOF
else
    echo "deb http://download.proxmox.com/debian/pve $CODENAME pve-no-subscription" > "$SL/pve-no-subscription.list"
fi

info "Actualizando Proxmox..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get -y full-upgrade
apt-get install -y lm-sensors smartmontools git htop curl

# ---------------------------------------------------------------------
# Comprobaciones
# ---------------------------------------------------------------------
if grep -qE 'vmx|svm' /proc/cpuinfo; then
    info "Virtualización por hardware disponible (VT-x/AMD-V)."
else
    aviso "La CPU no muestra VT-x: actívalo en la BIOS. Sin él no hay máquinas virtuales (los contenedores LXC sí funcionan)."
fi

sensors-detect --auto >/dev/null 2>&1 || true
echo
info "Temperaturas del host:"
sensors 2>/dev/null | grep -E 'Package|Core|Composite' || aviso "sin sensores (normal si Proxmox está dentro de una VM)"

echo
info "Discos detectados (para montar el externo, ver docs/04-instalacion.md):"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL
echo
info "Listo. Si se ha actualizado el kernel, reinicia: reboot"
info "Siguiente paso: bash proxmox/02-crear-ct-minecraft.sh"
