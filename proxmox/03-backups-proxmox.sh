#!/usr/bin/env bash
# =====================================================================
#  P3 — Copias completas de los contenedores con vzdump
#  Ejecutar EN EL PROXMOX como root:  bash proxmox/03-backups-proxmox.sh
#
#  Hay DOS niveles de copia en el proyecto:
#   1. Dentro del CT (scripts/04-setup-backups.sh): solo el MUNDO de
#      Minecraft, cada noche. Rápida de restaurar si se rompe el mundo.
#   2. Aquí (vzdump): el CONTENEDOR ENTERO (sistema, configuración,
#      mundo), cada semana. Sirve si se rompe todo el CT o el SSD.
#
#  Qué hace:
#   - Registra el disco externo como almacenamiento "externo" de Proxmox
#   - Crea una tarea de copia semanal del CT $CTID (se ve en la web:
#     Centro de datos → Copia de seguridad)
# =====================================================================
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/proxmox.env"

info()  { echo -e "\033[0;32m[+]\033[0m $*"; }
aviso() { echo -e "\033[0;33m[!]\033[0m $*"; }
error() { echo -e "\033[0;31m[x]\033[0m $*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || error "Ejecútalo como root en el Proxmox."
mountpoint -q "$EXTERNAL_MOUNT" || error "El disco externo no está montado en $EXTERNAL_MOUNT (ver docs/04-instalacion.md)."

mkdir -p "$PROXMOX_BACKUP_DIR"
if ! pvesm status | awk '{print $1}' | grep -qx externo; then
    info "Añadiendo el almacenamiento 'externo' ($PROXMOX_BACKUP_DIR)..."
    # is_mountpoint: si el disco no está conectado, Proxmox NO escribe en el SSD por error
    pvesm add dir externo --path "$PROXMOX_BACKUP_DIR" --content backup --is_mountpoint "$EXTERNAL_MOUNT"
fi
pvesm status

if pvesh get /cluster/backup --output-format json | grep -q '"comment":"proyecto-ct'"$CTID"'"'; then
    aviso "La tarea de copia del CT $CTID ya existe."
else
    info "Creando copia semanal del CT $CTID ($VZDUMP_SCHEDULE, $VZDUMP_KEEP)..."
    pvesh create /cluster/backup \
        --vmid "$CTID" \
        --storage externo \
        --schedule "$VZDUMP_SCHEDULE" \
        --mode snapshot \
        --compress zstd \
        --prune-backups "$VZDUMP_KEEP" \
        --enabled 1 \
        --comment "proyecto-ct$CTID"
fi

echo
read -r -p "¿Hacer ahora una primera copia de prueba del CT $CTID? [s/N] " r || r=n
if [[ "$r" =~ ^[sS]$ ]]; then
    vzdump "$CTID" --storage externo --mode snapshot --compress zstd
    ls -lh "$PROXMOX_BACKUP_DIR/dump/"
fi
info "Restaurar una copia: ver docs/05-seguridad.md (apartado Proxmox)."
