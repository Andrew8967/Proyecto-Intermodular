#!/usr/bin/env bash
# =====================================================================
#  02 — Servidor de Minecraft con PaperMC (servicio systemd)
#  Ejecutar con: sudo bash 02-install-papermc.sh
#
#  Qué hace:
#   1. Instala Java y crea el usuario de sistema "minecraft" (sin login)
#   2. Descarga PaperMC desde la API oficial y COMPRUEBA su SHA-256
#   3. Genera server.properties con RCON activado solo en local
#      (el panel lo usa para leer TPS y jugadores)
#   4. Crea el servicio minecraft.service con flags de Aikar para Java
#  Si ya está instalado, actualiza paper.jar y respeta tu configuración.
# =====================================================================
source "$(dirname "$0")/lib.sh"
require_root
require_debian
load_config

info "Instalando Java ($JAVA_PACKAGE)..."
apt-get update
apt-get install -y "$JAVA_PACKAGE" python3 curl
java -version

# usuario propio para el servidor: si alguien lo hackea, no tiene acceso al resto
if ! id "$MC_USER" >/dev/null 2>&1; then
    info "Creando usuario de sistema '$MC_USER'..."
    useradd --system --home-dir "$MC_DIR" --create-home --shell /usr/sbin/nologin "$MC_USER"
fi
mkdir -p "$MC_DIR"

# ---------------------------------------------------------------------
# Descarga de PaperMC
#   API nueva (Fill v3): https://fill.papermc.io/v3/...
#   Si falla, se intenta la API antigua (v2) como plan B.
# ---------------------------------------------------------------------
info "Buscando la última build de Paper $PAPER_VERSION..."
UA="ProyectoIntermodular-SMR/2.0 (servidor educativo)"
read -r JAR_URL JAR_SHA < <(python3 - "$PAPER_VERSION" "$UA" <<'PY'
import json, sys, urllib.request
version, ua = sys.argv[1], sys.argv[2]
def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": ua})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)
try:  # API v3 (Fill)
    b = get(f"https://fill.papermc.io/v3/projects/paper/versions/{version}/builds/latest")
    d = b["downloads"]["server:default"]
    print(d["url"], d["checksums"]["sha256"])
except Exception:
    try:  # API v2 (antigua)
        builds = get(f"https://api.papermc.io/v2/projects/paper/versions/{version}/builds")["builds"]
        last = builds[-1]
        name = last["downloads"]["application"]["name"]
        sha = last["downloads"]["application"]["sha256"]
        print(f"https://api.papermc.io/v2/projects/paper/versions/{version}/builds/{last['build']}/downloads/{name}", sha)
    except Exception as e:
        print("ERROR", e)
PY
) || true
[ -n "${JAR_URL:-}" ] && [ "$JAR_URL" != "ERROR" ] && [ -n "${JAR_SHA:-}" ] \
    || error "No pude encontrar Paper $PAPER_VERSION. Revisa PAPER_VERSION en config.env."

TMP_JAR="$(mktemp)"
curl -fL --retry 3 -A "$UA" -o "$TMP_JAR" "$JAR_URL"
echo "$JAR_SHA  $TMP_JAR" | sha256sum -c --quiet - \
    || { rm -f "$TMP_JAR"; error "El SHA-256 de la descarga no coincide. No instalo nada."; }
install -m 644 -o "$MC_USER" -g "$MC_USER" "$TMP_JAR" "$MC_DIR/paper.jar"
rm -f "$TMP_JAR"
info "paper.jar instalado y verificado (sha256 OK)."

# ---------------------------------------------------------------------
# Configuración del servidor (solo la primera vez)
# ---------------------------------------------------------------------
echo "eula=true" > "$MC_DIR/eula.txt"

if [ ! -f "$MC_DIR/server.properties" ]; then
    info "Generando server.properties..."
    RCON_PASS="$(head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)"
    cat > "$MC_DIR/server.properties" <<EOF
motd=$MC_MOTD
server-port=25565
max-players=$MC_MAX_PLAYERS
online-mode=true
white-list=$MC_WHITELIST
enforce-whitelist=$MC_WHITELIST
difficulty=normal
gamemode=survival
level-name=world
view-distance=$MC_VIEW_DISTANCE
simulation-distance=$MC_SIMULATION_DISTANCE
enable-status=true
# RCON: lo usa el panel para leer TPS y jugadores. El firewall NO abre este puerto.
enable-rcon=true
rcon.port=$RCON_PORT
rcon.password=$RCON_PASS
broadcast-rcon-to-ops=false
EOF
else
    aviso "server.properties ya existe: no lo toco."
    [ "$(prop_get "$MC_DIR/server.properties" enable-rcon)" = "true" ] \
        || aviso "RCON está desactivado: el panel no podrá mostrar TPS ni nombres de jugadores."
fi
chown -R "$MC_USER:$MC_USER" "$MC_DIR"
chmod 750 "$MC_DIR"
chmod 640 "$MC_DIR/server.properties"   # contiene la contraseña de RCON

# ---------------------------------------------------------------------
# Servicio systemd
# ---------------------------------------------------------------------
info "Creando minecraft.service..."
# Flags de Aikar: configuración de memoria recomendada por la comunidad de Paper
JAVA_FLAGS="-Xms$MC_RAM -Xmx$MC_RAM -XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 \
-XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=30 \
-XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M -XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 \
-XX:G1MixedGCCountTarget=4 -XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 \
-XX:G1RSetUpdatingPauseIntervalMillis=100 -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem \
-XX:MaxTenuringThreshold=1 -Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true"

cat > /etc/systemd/system/minecraft.service <<EOF
[Unit]
Description=Servidor Minecraft (PaperMC $PAPER_VERSION)
After=network-online.target
Wants=network-online.target

[Service]
User=$MC_USER
Group=$MC_USER
WorkingDirectory=$MC_DIR
ExecStart=/usr/bin/java $JAVA_FLAGS -jar paper.jar --nogui
# Paper guarda el mundo al recibir SIGTERM; le damos tiempo para hacerlo
TimeoutStopSec=90
SuccessExitStatus=0 1 143
Restart=on-failure
RestartSec=15

# Endurecimiento: el proceso no puede tocar el resto del sistema
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
PrivateTmp=true
ReadWritePaths=$MC_DIR

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable minecraft
systemctl restart minecraft

info "Minecraft arrancando (el primer arranque genera el mundo y tarda 1-2 minutos)."
echo "    Ver el log en directo:   journalctl -u minecraft -f"
echo "    Conectar desde la LAN:   $SERVER_IP:25565"
if [ "$MC_WHITELIST" = "true" ]; then
    echo "    Whitelist activa. Para añadir jugadores, en el log o por RCON:  whitelist add <nombre>"
    echo "    (ver docs/04-instalacion.md, apartado Minecraft)"
fi
echo
info "Siguiente paso: sudo bash scripts/03-install-panel.sh"
