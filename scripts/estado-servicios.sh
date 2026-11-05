#!/usr/bin/env bash
# =====================================================================
#  Estado rápido del servidor: servicios, memoria, discos y puertos.
#  Uso:  bash estado-servicios.sh            (solo mirar)
#        sudo bash estado-servicios.sh --start   (arrancar los parados)
# =====================================================================
SERVICES=(ssh apache2 minecraft panel-status fail2ban minecraft-backup.timer ollama open-webui)

echo "== Servicios =="
for s in "${SERVICES[@]}"; do
    if systemctl list-unit-files "$s" "$s.service" --no-legend 2>/dev/null | grep -q .; then
        if [ "${1:-}" = "--start" ] && ! systemctl is-active -q "$s"; then
            systemctl start "$s" && echo "   (arrancado $s)"
        fi
        printf "  %-24s %s\n" "$s" "$(systemctl is-active "$s")"
    fi
done

echo; echo "== Memoria =="; free -h
echo; echo "== Discos ==";  df -h / /mnt/externo 2>/dev/null
echo; echo "== Temperatura =="; (sensors 2>/dev/null | grep -E 'Package|Core 0|Composite') || echo "  sin sensores (normal en una VM)"
echo; echo "== Puertos escuchando =="
ss -tuln | grep -E ':(22|80|25565|25575|11434|3000)\s' || echo "  ninguno de los esperados"
echo; echo "== Firewall =="; (sudo -n ufw status 2>/dev/null || echo "  ejecuta con sudo para ver UFW")
