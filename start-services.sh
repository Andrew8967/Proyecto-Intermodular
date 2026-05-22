#!/bin/bash
# arranca todos los servicios del servidor y muestra el estado

SERVICES=("ssh" "apache2" "minecraft" "ollama" "open-webui")

for service in "${SERVICES[@]}"; do
    if systemctl list-unit-files | grep -q "$service.service"; then
        sudo systemctl start "$service" 2>/dev/null && echo "$service iniciado" || echo "error al iniciar $service"
    fi
done

echo ""
for service in "${SERVICES[@]}"; do
    if systemctl list-unit-files | grep -q "$service.service"; then
        STATUS=$(systemctl is-active "$service" 2>/dev/null || echo "inactivo")
        printf "%-20s %s\n" "$service" "$STATUS"
    fi
done

echo ""
free -h | grep Mem
ss -tulnp | grep -E ":(22|80|443|25565|11434|3000) " | awk '{print $1, $5}' | sort -t: -k2 -n
