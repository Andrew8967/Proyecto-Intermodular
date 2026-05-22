#!/bin/bash
# instala papermc y configura el servicio en el sistema

MINECRAFT_DIR="/home/pi/minecraft"
PAPER_VERSION="1.21.4"
RAM_MAX="2G"
RAM_MIN="1G"

if ! command -v java &> /dev/null; then
    sudo apt update && sudo apt install openjdk-21-jre-headless -y
fi

mkdir -p "$MINECRAFT_DIR"
cd "$MINECRAFT_DIR"

wget -q "https://api.papermc.io/v2/projects/paper/versions/${PAPER_VERSION}/builds/latest/downloads/paper-${PAPER_VERSION}-latest.jar" -O paper.jar

echo "eula=true" > eula.txt

cat > server.properties << PROPS
motd=Servidor Personal - Raspberry Pi 5
server-port=25565
max-players=5
online-mode=true
difficulty=normal
gamemode=survival
view-distance=8
simulation-distance=6
level-name=mundo
white-list=false
PROPS

sudo tee /etc/systemd/system/minecraft.service > /dev/null << SERVICE
[Unit]
Description=Servidor de Minecraft PaperMC
After=network.target

[Service]
User=pi
WorkingDirectory=${MINECRAFT_DIR}
ExecStart=/usr/bin/java -Xmx${RAM_MAX} -Xms${RAM_MIN} -XX:+UseG1GC -jar paper.jar nogui
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
SERVICE

sudo systemctl daemon-reload
sudo systemctl enable minecraft
echo "instalacion completada, arrancar con: sudo systemctl start minecraft"
