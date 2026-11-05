#!/usr/bin/env bash
# Funciones comunes para todos los scripts del proyecto.
# No se ejecuta directamente: los demás scripts lo cargan con "source".

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# colores para que los mensajes se lean mejor
VERDE='\033[0;32m'; AMARILLO='\033[0;33m'; ROJO='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${VERDE}[+]${NC} $*"; }
aviso() { echo -e "${AMARILLO}[!]${NC} $*"; }
error() { echo -e "${ROJO}[x]${NC} $*" >&2; exit 1; }

# estos scripts cambian configuración del sistema: tienen que ir con sudo
require_root() {
    [ "$(id -u)" -eq 0 ] || error "Ejecuta este script con sudo: sudo bash $0"
}

# solo funcionan en Debian/Ubuntu (usan apt y systemd)
require_debian() {
    command -v apt-get >/dev/null || error "Este script es para Debian/Ubuntu (no encuentro apt-get)."
    command -v systemctl >/dev/null || error "Hace falta systemd."
}

# carga config.env y comprueba lo básico
load_config() {
    local cfg="$SCRIPT_DIR/config.env"
    [ -f "$cfg" ] || error "No encuentro $cfg"
    # shellcheck source=config.env
    source "$cfg"
    if [ -z "${ADMIN_USER:-}" ]; then
        ADMIN_USER="${SUDO_USER:-}"
    fi
    [ -n "$ADMIN_USER" ] && [ "$ADMIN_USER" != "root" ] \
        || error "Define ADMIN_USER en config.env (tu usuario normal, no root)."
    id "$ADMIN_USER" >/dev/null 2>&1 || error "El usuario '$ADMIN_USER' no existe."
}

# lee un valor de un archivo clave=valor (por ejemplo server.properties)
prop_get() {
    local file="$1" key="$2"
    grep -E "^${key}=" "$file" 2>/dev/null | head -1 | cut -d= -f2-
}
