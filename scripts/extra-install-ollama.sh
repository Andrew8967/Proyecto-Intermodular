#!/usr/bin/env bash
# =====================================================================
#  EXTRA (opcional) — Chatbot de IA local: Ollama + Open WebUI
#  NO forma parte del núcleo del proyecto. Instálalo solo si sobra tiempo.
#  Ejecutar con: sudo bash extra-install-ollama.sh
#
#  Notas:
#   - Funciona solo con CPU. En un i3 un modelo pequeño (phi3:mini, ~2.3 GB)
#     responde, pero tarda varios segundos por respuesta.
#   - Open WebUI se instala con Docker porque su paquete de pip pide
#     Python 3.11 y Debian 13 trae Python 3.13.
#   - Ollama escucha solo en 127.0.0.1:11434. Open WebUI en el puerto 3000.
# =====================================================================
source "$(dirname "$0")/lib.sh"
require_root
require_debian
load_config

MODEL="${OLLAMA_MODEL:-phi3:mini}"
WEBUI_PORT=3000

info "Instalando Ollama (instalador oficial)..."
apt-get install -y curl zstd
if ! command -v ollama >/dev/null; then
    curl -fsSL https://ollama.com/install.sh -o /tmp/ollama-install.sh
    sh /tmp/ollama-install.sh
    rm -f /tmp/ollama-install.sh
fi
systemctl enable --now ollama
info "Descargando el modelo $MODEL (puede tardar)..."
ollama pull "$MODEL"

info "Instalando Docker y Open WebUI..."
apt-get install -y docker.io
systemctl enable --now docker
docker rm -f open-webui >/dev/null 2>&1 || true
docker run -d --name open-webui --restart unless-stopped \
    --network host \
    -e PORT=$WEBUI_PORT \
    -e OLLAMA_BASE_URL=http://127.0.0.1:11434 \
    -v open-webui:/app/backend/data \
    ghcr.io/open-webui/open-webui:main

ufw allow from "$LAN_SUBNET" to any port $WEBUI_PORT proto tcp comment 'Open WebUI (LAN)'

info "Chat disponible en http://$SERVER_IP:$WEBUI_PORT (el primer usuario que se registra es el administrador)."
aviso "Añade 'ollama docker' a PANEL_SERVICES en config.env si quieres verlos en el panel."
