#!/usr/bin/env bash
# =====================================================================
#  04 — Copias de seguridad automáticas del mundo de Minecraft
#  Ejecutar con: sudo bash 04-setup-backups.sh
#
#  Qué hace:
#   - Instala /usr/local/bin/backup-minecraft (el script de copia)
#   - Crea un temporizador systemd que lo lanza cada noche a $BACKUP_TIME
#   - Las copias van al disco externo ($BACKUP_DIR) y se guardan las
#     últimas $BACKUP_KEEP. Si el disco externo no está montado, NO copia
#     (para no llenar el SSD del sistema sin darte cuenta).
#
#  Copia manual en cualquier momento:   sudo backup-minecraft
#  Restaurar una copia:                 ver docs/05-seguridad.md
# =====================================================================
source "$(dirname "$0")/lib.sh"
require_root
require_debian
load_config

install -d /etc/proyecto-servidor
cat > /etc/proyecto-servidor/backup.env <<EOF
MC_DIR=$MC_DIR
MC_USER=$MC_USER
EXTERNAL_MOUNT=$EXTERNAL_MOUNT
BACKUP_DIR=$BACKUP_DIR
BACKUP_KEEP=$BACKUP_KEEP
EOF

info "Instalando /usr/local/bin/backup-minecraft..."
cat > /usr/local/bin/backup-minecraft <<'EOF'
#!/usr/bin/env bash
# Copia de seguridad del mundo de Minecraft (generado por 04-setup-backups.sh)
set -euo pipefail
source /etc/proyecto-servidor/backup.env

if ! mountpoint -q "$EXTERNAL_MOUNT"; then
    echo "El disco externo no está montado en $EXTERNAL_MOUNT: no hago la copia." >&2
    exit 1
fi
mkdir -p "$BACKUP_DIR"

rcon() { [ -x /usr/local/bin/mc-cmd ] && /usr/local/bin/mc-cmd "$@" >/dev/null 2>&1 || true; }

# Si el servidor está encendido: guardar todo y pausar el autoguardado
# mientras se copia, para que el mundo no cambie a mitad de la copia.
if systemctl is-active -q minecraft; then
    rcon "say Copia de seguridad en curso..."
    rcon "save-off"
    rcon "save-all flush"
    sleep 5
fi
trap 'systemctl is-active -q minecraft && rcon "save-on"' EXIT

FILE="$BACKUP_DIR/mundo-$(date +%F_%H%M).tar.gz"
cd "$MC_DIR"
WORLDS=$(find . -maxdepth 1 -type d -name 'world*' -printf '%f ')
# shellcheck disable=SC2086
tar -czf "$FILE" $WORLDS server.properties whitelist.json ops.json 2>/dev/null || \
    tar -czf "$FILE" $WORLDS
rcon "save-on"
rcon "say Copia de seguridad terminada."

# comprobar que el archivo se puede leer (una copia que no se abre no sirve)
tar -tzf "$FILE" >/dev/null
echo "Copia creada: $FILE ($(du -h "$FILE" | cut -f1))"

# borrar las más antiguas, dejando solo BACKUP_KEEP
ls -1t "$BACKUP_DIR"/mundo-*.tar.gz | tail -n +"$((BACKUP_KEEP + 1))" | xargs -r rm -f
EOF
chmod 750 /usr/local/bin/backup-minecraft

cat > /etc/systemd/system/minecraft-backup.service <<EOF
[Unit]
Description=Copia de seguridad del mundo de Minecraft

[Service]
Type=oneshot
ExecStart=/usr/local/bin/backup-minecraft
EOF

cat > /etc/systemd/system/minecraft-backup.timer <<EOF
[Unit]
Description=Copia de seguridad diaria de Minecraft ($BACKUP_TIME)

[Timer]
OnCalendar=*-*-* $BACKUP_TIME:00
# si el servidor estaba apagado a esa hora, la hace al encender
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now minecraft-backup.timer

if mountpoint -q "$EXTERNAL_MOUNT"; then
    info "Disco externo montado en $EXTERNAL_MOUNT. Haciendo una primera copia de prueba..."
    /usr/local/bin/backup-minecraft || aviso "La copia de prueba falló: journalctl -u minecraft-backup"
else
    aviso "El disco externo NO está montado en $EXTERNAL_MOUNT."
    aviso "Móntalo siguiendo docs/04-instalacion.md (apartado 'Disco externo') y prueba: sudo backup-minecraft"
fi
systemctl list-timers minecraft-backup.timer --no-pager
