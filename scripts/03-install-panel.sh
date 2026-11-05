#!/usr/bin/env bash
# =====================================================================
#  03 — Panel web de monitorización (Apache2 + recolector de datos)
#  Ejecutar con: sudo bash 03-install-panel.sh
#
#  Cómo funciona:
#    panel-status.py  --(cada 10 s)-->  /var/www/html/data/status.json
#    Navegador  --fetch()-->  Apache2  --> status.json --> se pinta el panel
#
#  Qué hace:
#   1. Instala Apache2 y oculta su versión (ServerTokens Prod)
#   2. Copia la web de panel-web/ a /var/www/html
#   3. Instala el recolector como servicio systemd (panel-status)
#   4. Instala el comando "mc-cmd" para mandar órdenes a Minecraft
#  Para actualizar la web tras cambiar el HTML, vuelve a ejecutarlo.
# =====================================================================
source "$(dirname "$0")/lib.sh"
require_root
require_debian
load_config

id "$MC_USER" >/dev/null 2>&1 || error "Primero instala Minecraft (02-install-papermc.sh)."

info "Instalando Apache2..."
apt-get update
apt-get install -y apache2 python3

# no enseñar la versión de Apache ni del sistema en las cabeceras y errores
SEC=/etc/apache2/conf-available/security.conf
sed -i 's/^ServerTokens .*/ServerTokens Prod/; s/^ServerSignature .*/ServerSignature Off/' "$SEC"
cat > /etc/apache2/conf-available/panel.conf <<EOF
# Generado por 03-install-panel.sh
<Directory $WEB_ROOT>
    Options -Indexes
</Directory>
# status.json cambia cada pocos segundos: que el navegador no lo guarde en caché
<Location "/data/">
    Header set Cache-Control "no-store"
</Location>
Header always set X-Content-Type-Options "nosniff"
Header always set X-Frame-Options "SAMEORIGIN"
EOF
a2enmod headers >/dev/null
a2enconf panel >/dev/null

info "Copiando la web a $WEB_ROOT..."
[ -f "$WEB_ROOT/index.html" ] && [ ! -f "$WEB_ROOT/.panel" ] && \
    mv "$WEB_ROOT/index.html" "$WEB_ROOT/index.apache-original.html"
cp -r "$REPO_DIR/panel-web/." "$WEB_ROOT/"
touch "$WEB_ROOT/.panel"
mkdir -p "$WEB_ROOT/data"
chown root:root -R "$WEB_ROOT"
chown "$MC_USER:www-data" "$WEB_ROOT/data"   # solo el recolector puede escribir aquí
chmod 755 "$WEB_ROOT/data"

apache2ctl configtest
systemctl enable apache2
systemctl restart apache2     # restart (no reload) para cargar el módulo headers

# ---------------------------------------------------------------------
# Recolector de datos
# ---------------------------------------------------------------------
info "Instalando el recolector panel-status..."
install -d /opt/panel-status /etc/proyecto-servidor
install -m 755 "$SCRIPT_DIR/panel/panel-status.py" /opt/panel-status/panel-status.py

cat > /etc/proyecto-servidor/panel.env <<EOF
# Generado por 03-install-panel.sh a partir de scripts/config.env
MC_HOST=127.0.0.1
MC_PORT=25565
MC_DIR=$MC_DIR
PANEL_OUTPUT=$WEB_ROOT/data/status.json
PANEL_STATE=/var/lib/panel-status/state.json
PANEL_INTERVAL=$PANEL_INTERVAL
PANEL_SERVICES="$PANEL_SERVICES"
PANEL_DISKS="$PANEL_DISKS"
SERVER_IP=$SERVER_IP
LAN_SUBNET=$LAN_SUBNET
EOF

cat > /etc/systemd/system/panel-status.service <<EOF
[Unit]
Description=Recolector de datos del panel de monitorización
After=network-online.target minecraft.service

[Service]
Type=simple
# Corre como el usuario de Minecraft: puede leer la contraseña de RCON y el tamaño del mundo
User=$MC_USER
Group=$MC_USER
EnvironmentFile=/etc/proyecto-servidor/panel.env
ExecStart=/usr/bin/python3 /opt/panel-status/panel-status.py
StateDirectory=panel-status
Restart=always
RestartSec=5

NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=$WEB_ROOT/data

[Install]
WantedBy=multi-user.target
EOF

# comando corto para hablar con la consola de Minecraft: sudo mc-cmd "whitelist add Steve"
cat > /usr/local/bin/mc-cmd <<EOF
#!/usr/bin/env bash
# Envía un comando a la consola de Minecraft por RCON. Ejemplo: sudo mc-cmd "list"
[ "\$(id -u)" -eq 0 ] || { echo "Usa: sudo mc-cmd \"comando\""; exit 1; }
[ \$# -gt 0 ] || { echo "Uso: sudo mc-cmd \"comando\"   (ej: sudo mc-cmd \"whitelist add Steve\")"; exit 1; }
exec runuser -u $MC_USER -- env MC_DIR=$MC_DIR /usr/bin/python3 /opt/panel-status/panel-status.py --rcon "\$*"
EOF
chmod 755 /usr/local/bin/mc-cmd

systemctl daemon-reload
systemctl enable panel-status
systemctl restart panel-status

sleep 3
if [ -s "$WEB_ROOT/data/status.json" ]; then
    info "status.json generado correctamente."
else
    aviso "Aún no hay status.json. Mira el log: journalctl -u panel-status -n 30"
fi
echo
info "Panel disponible en:  http://$SERVER_IP/"
echo "    Estado del recolector:  systemctl status panel-status"
echo "    Ver los datos:          python3 -m json.tool $WEB_ROOT/data/status.json | less"
echo "    Consola Minecraft:      sudo mc-cmd \"list\""
echo
info "Siguiente paso: sudo bash scripts/04-setup-backups.sh"
