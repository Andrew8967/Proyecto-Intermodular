#!/bin/bash
# instala ollama y la interfaz web para el chatbot local

WEBUI_PORT=3000
MODEL="phi3:mini"

curl -fsSL https://ollama.com/install.sh | sh

ollama pull "$MODEL"

sudo apt install python3-pip python3-venv -y
python3 -m venv /home/pi/venv-webui
/home/pi/venv-webui/bin/pip install open-webui

sudo tee /etc/systemd/system/open-webui.service > /dev/null << SERVICE
[Unit]
Description=Open WebUI interfaz para Ollama
After=network.target ollama.service

[Service]
User=pi
WorkingDirectory=/home/pi
ExecStart=/home/pi/venv-webui/bin/open-webui serve --host 0.0.0.0 --port ${WEBUI_PORT}
Restart=on-failure
RestartSec=10
Environment=OLLAMA_BASE_URL=http://localhost:11434

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable open-webui
echo "acceder al chat en: http://192.168.1.100:${WEBUI_PORT}"
