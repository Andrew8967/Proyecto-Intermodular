#!/usr/bin/env python3
"""
panel-status.py — Recolector de datos para el panel de monitorización.

Cada PANEL_INTERVAL segundos lee:
  - Minecraft: estado, jugadores, ping y versión  (protocolo "Server List Ping")
  - Minecraft: TPS, MSPT y nombres de jugadores   (RCON, solo en localhost)
  - Sistema:   CPU, RAM, temperaturas, discos, uptime, servicios systemd
y lo escribe en un archivo JSON (status.json) que la página web lee con fetch().

La web es estática (HTML/CSS/JS en Apache): no puede leer el sistema por sí
sola. Este script hace de "puente" entre el servidor y la página.

Solo usa la librería estándar de Python 3 (no hace falta pip).

Uso:
  panel-status.py                    # bucle infinito (lo lanza systemd)
  panel-status.py --once --stdout    # una lectura y la muestra por pantalla
  panel-status.py --rcon "list"      # envía un comando a la consola de Minecraft
"""

import argparse
import json
import os
import platform
import re
import shutil
import socket
import struct
import subprocess
import sys
import time
from collections import deque

# ---------------------------------------------------------------------------
# Configuración (llega como variables de entorno desde /etc/proyecto-servidor/panel.env)
# ---------------------------------------------------------------------------
CFG = {
    "MC_HOST": os.environ.get("MC_HOST", "127.0.0.1"),
    "MC_PORT": int(os.environ.get("MC_PORT", "25565")),
    "MC_DIR": os.environ.get("MC_DIR", "/opt/minecraft"),
    "OUTPUT": os.environ.get("PANEL_OUTPUT", "/var/www/html/data/status.json"),
    "STATE": os.environ.get("PANEL_STATE", "/var/lib/panel-status/state.json"),
    "INTERVAL": int(os.environ.get("PANEL_INTERVAL", "10")),
    "SERVICES": os.environ.get("PANEL_SERVICES", "ssh apache2 minecraft").split(),
    "DISKS": os.environ.get("PANEL_DISKS", "Sistema=/"),
    "SERVER_IP": os.environ.get("SERVER_IP", ""),
    "LAN_SUBNET": os.environ.get("LAN_SUBNET", ""),
}
HISTORY_LEN = 90      # 90 muestras x 10 s = 15 minutos de gráfica
EVENTS_LEN = 30       # últimos 30 eventos (caídas, arranques...)
WORLD_SIZE_EVERY = 60  # medir el tamaño del mundo es lento: cada 60 s


# ===========================================================================
#  MINECRAFT — Server List Ping (lo mismo que hace el juego en "Multijugador")
#  https://minecraft.wiki/w/Java_Edition_protocol/Server_List_Ping
# ===========================================================================
def _varint(n):
    n &= 0xFFFFFFFF
    out = b""
    while True:
        b = n & 0x7F
        n >>= 7
        out += struct.pack("B", b | (0x80 if n else 0))
        if not n:
            return out


def _recv_exact(sock, n):
    data = b""
    while len(data) < n:
        chunk = sock.recv(n - len(data))
        if not chunk:
            raise ConnectionError("conexión cerrada")
        data += chunk
    return data


def _read_varint(sock):
    num = 0
    for i in range(5):
        b = _recv_exact(sock, 1)[0]
        num |= (b & 0x7F) << (7 * i)
        if not b & 0x80:
            return num
    raise ValueError("varint demasiado largo")


def _text_of(component):
    """El MOTD puede venir como texto o como 'componente' JSON con 'extra'."""
    if isinstance(component, str):
        return component
    if isinstance(component, dict):
        return component.get("text", "") + "".join(_text_of(c) for c in component.get("extra", []))
    if isinstance(component, list):
        return "".join(_text_of(c) for c in component)
    return ""


def server_list_ping(host, port, timeout=3.0):
    with socket.create_connection((host, port), timeout=timeout) as s:
        s.settimeout(timeout)
        hb = host.encode()
        handshake = _varint(0) + _varint(-1) + _varint(len(hb)) + hb + struct.pack(">H", port) + _varint(1)
        s.sendall(_varint(len(handshake)) + handshake)
        s.sendall(b"\x01\x00")                       # petición de estado
        _read_varint(s)                              # longitud del paquete
        _read_varint(s)                              # id del paquete
        status = json.loads(_recv_exact(s, _read_varint(s)).decode("utf-8"))
        # ping/pong para medir la latencia
        t0 = time.perf_counter()
        s.sendall(_varint(9) + b"\x01" + struct.pack(">q", int(time.time() * 1000)))
        _read_varint(s)
        _read_varint(s)
        _recv_exact(s, 8)
        ping_ms = (time.perf_counter() - t0) * 1000
    players = status.get("players", {})
    return {
        "version": status.get("version", {}).get("name"),
        "motd": re.sub(r"§.", "", _text_of(status.get("description", ""))).strip(),
        "players_online": players.get("online", 0),
        "max": players.get("max", 0),
        "sample": [p.get("name") for p in players.get("sample", []) if p.get("name")],
        "ping_ms": round(ping_ms, 1),
    }


# ===========================================================================
#  MINECRAFT — RCON (consola remota). Solo escucha en el propio servidor.
#  https://minecraft.wiki/w/RCON
# ===========================================================================
class Rcon:
    def __init__(self, host, port, password, timeout=3.0):
        self.sock = socket.create_connection((host, port), timeout=timeout)
        self.sock.settimeout(timeout)
        self._id = 0
        if self._send(3, password)[0] == -1:
            self.close()
            raise PermissionError("contraseña de RCON incorrecta")

    def _send(self, ptype, body):
        self._id += 1
        payload = struct.pack("<ii", self._id, ptype) + body.encode("utf-8") + b"\x00\x00"
        self.sock.sendall(struct.pack("<i", len(payload)) + payload)
        length = struct.unpack("<i", _recv_exact(self.sock, 4))[0]
        data = _recv_exact(self.sock, length)
        req_id, _ = struct.unpack("<ii", data[:8])
        return req_id, data[8:-2].decode("utf-8", "replace")

    def command(self, cmd):
        return self._send(2, cmd)[1]

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


def read_properties(path):
    props = {}
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    props[k] = v
    except OSError:
        pass
    return props


def open_rcon():
    props = read_properties(os.path.join(CFG["MC_DIR"], "server.properties"))
    if props.get("enable-rcon") != "true" or not props.get("rcon.password"):
        return None
    return Rcon("127.0.0.1", int(props.get("rcon.port", "25575")), props["rcon.password"])


def strip_colors(text):
    return re.sub(r"§.", "", text)


def parse_tps(text):
    """'TPS from last 1m, 5m, 15m: *20.0, 19.98, 19.9' -> [20.0, 19.98, 19.9]"""
    text = strip_colors(text)
    if ":" not in text:
        return None
    nums = re.findall(r"\d+(?:\.\d+)?", text.rsplit(":", 1)[1])
    return [min(float(n), 20.0) for n in nums[:3]] or None


def parse_mspt(text):
    """Paper: 'Server tick times (avg/min/max) from last 5s, 10s, 1m:\n◴ 1.2/0.4/5.0, ...'"""
    lines = strip_colors(text).splitlines()
    if len(lines) < 2:
        return None
    m = re.search(r"(\d+(?:\.\d+)?)/", lines[1])
    return float(m.group(1)) if m else None


def parse_list(text):
    """'There are 2 of a max of 10 players online: Steve, Alex' -> ['Steve', 'Alex']"""
    text = strip_colors(text)
    if ":" not in text:
        return []
    names = text.split(":", 1)[1].strip()
    return [n.strip() for n in names.split(",") if n.strip()]


def minecraft_status():
    mc = {"online": False}
    try:
        mc.update(server_list_ping(CFG["MC_HOST"], CFG["MC_PORT"]))
        mc["online"] = True
        mc["players"] = mc.pop("sample")
    except (OSError, ValueError, json.JSONDecodeError) as e:
        mc["error"] = str(e)
        return mc
    rcon = None
    try:
        rcon = open_rcon()
        if rcon:
            mc["tps"] = parse_tps(rcon.command("tps"))
            mc["mspt"] = parse_mspt(rcon.command("mspt"))
            mc["players"] = parse_list(rcon.command("list")) or mc["players"]
    except (OSError, ValueError, PermissionError) as e:
        mc["rcon_error"] = str(e)
    finally:
        if rcon:
            rcon.close()
    return mc


# ===========================================================================
#  SISTEMA — todo sale de /proc y /sys (archivos especiales de Linux)
# ===========================================================================
def _read(path, default=""):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return default


def cpu_times():
    fields = _read("/proc/stat").splitlines()[0].split()[1:]
    vals = [int(x) for x in fields]
    idle = vals[3] + (vals[4] if len(vals) > 4 else 0)   # idle + iowait
    return idle, sum(vals)


def cpu_percent(interval=0.5):
    try:
        i1, t1 = cpu_times()
        time.sleep(interval)
        i2, t2 = cpu_times()
        return round(100.0 * (1 - (i2 - i1) / max(t2 - t1, 1)), 1)
    except (IndexError, ValueError):
        return None


def memory():
    info = {}
    for line in _read("/proc/meminfo").splitlines():
        k, _, v = line.partition(":")
        info[k] = int(v.split()[0]) * 1024 if v.split() else 0
    total, avail = info.get("MemTotal", 0), info.get("MemAvailable", 0)
    if not total:
        return None
    return {"total": total, "used": total - avail, "percent": round(100 * (total - avail) / total, 1),
            "swap_total": info.get("SwapTotal", 0), "swap_used": info.get("SwapTotal", 0) - info.get("SwapFree", 0)}


def temperatures():
    """Lee los sensores de /sys/class/hwmon (coretemp = CPU Intel, nvme = SSD...)."""
    sensors = []
    base = "/sys/class/hwmon"
    if os.path.isdir(base):
        for hw in sorted(os.listdir(base)):
            d = os.path.join(base, hw)
            name = _read(os.path.join(d, "name")).strip() or hw
            for f in sorted(os.listdir(d)):
                if re.fullmatch(r"temp\d+_input", f):
                    raw = _read(os.path.join(d, f)).strip()
                    if raw.lstrip("-").isdigit():
                        label = _read(os.path.join(d, f.replace("_input", "_label"))).strip() or f.split("_")[0]
                        sensors.append({"chip": name, "label": label, "celsius": round(int(raw) / 1000, 1)})
    cpu = [s["celsius"] for s in sensors if s["chip"] in ("coretemp", "k10temp", "zenpower")]
    if not cpu:  # plan B: zonas térmicas ACPI
        cpu = [s["celsius"] for s in sensors if s["chip"] in ("acpitz", "x86_pkg_temp")]
    return {"cpu": max(cpu) if cpu else None, "sensors": sensors[:12]}


def disks():
    result = []
    for item in CFG["DISKS"].split(","):
        if "=" not in item:
            continue
        name, path = (x.strip() for x in item.split("=", 1))
        if not os.path.isdir(path):
            result.append({"name": name, "path": path, "mounted": False})
            continue
        # si no es un punto de montaje real, el "disco externo" sería el del sistema
        mounted = path == "/" or os.path.ismount(path)
        u = shutil.disk_usage(path)
        result.append({"name": name, "path": path, "mounted": mounted, "total": u.total,
                       "used": u.used, "percent": round(100 * u.used / u.total, 1) if u.total else 0})
    return result


def dir_size(path):
    total = 0
    for root, _, files in os.walk(path):
        for f in files:
            try:
                total += os.path.getsize(os.path.join(root, f))
            except OSError:
                pass
    return total


def world_size():
    base = CFG["MC_DIR"]
    if not os.path.isdir(base):
        return None
    worlds = [os.path.join(base, d) for d in os.listdir(base)
              if d.startswith("world") and os.path.isdir(os.path.join(base, d))]
    return sum(dir_size(w) for w in worlds) if worlds else None


def services():
    out = {}
    for svc in CFG["SERVICES"]:
        try:
            r = subprocess.run(["systemctl", "is-active", svc], capture_output=True, text=True, timeout=5)
            out[svc] = r.stdout.strip() or "unknown"
        except (OSError, subprocess.SubprocessError):
            out[svc] = "unknown"
    return out


def default_gateway():
    for line in _read("/proc/net/route").splitlines()[1:]:
        f = line.split()
        if len(f) > 2 and f[1] == "00000000":
            return socket.inet_ntoa(struct.pack("<L", int(f[2], 16)))
    return None


def local_ip():
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("192.0.2.1", 9))   # no envía nada, solo elige la interfaz
            return s.getsockname()[0]
    except OSError:
        return None


def host_info():
    os_name = "Linux"
    for line in _read("/etc/os-release").splitlines():
        if line.startswith("PRETTY_NAME="):
            os_name = line.split("=", 1)[1].strip('"')
    cpu_model = None
    for line in _read("/proc/cpuinfo").splitlines():
        if line.startswith("model name"):
            cpu_model = re.sub(r"\s+", " ", line.split(":", 1)[1]).strip()
            break
    virt = None
    try:
        r = subprocess.run(["systemd-detect-virt"], capture_output=True, text=True, timeout=5)
        virt = r.stdout.strip() if r.returncode == 0 else "none"
    except (OSError, subprocess.SubprocessError):
        pass
    return {"hostname": socket.gethostname(), "os": os_name, "kernel": platform.release(),
            "arch": platform.machine(), "cpu_model": cpu_model, "cores": os.cpu_count(),
            "virtualization": virt}


def uptime_seconds():
    try:
        return int(float(_read("/proc/uptime").split()[0]))
    except (IndexError, ValueError):
        return None


# ===========================================================================
#  Estado persistente: historial para las gráficas y eventos (caídas)
# ===========================================================================
class State:
    def __init__(self, path):
        self.path = path
        self.history = deque(maxlen=HISTORY_LEN)
        self.events = deque(maxlen=EVENTS_LEN)
        self.mc_online = None
        try:
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
            self.history.extend(data.get("history", []))
            self.events.extend(data.get("events", []))
            self.mc_online = data.get("mc_online")
        except (OSError, ValueError):
            pass

    def add_event(self, kind, text):
        self.events.append({"t": int(time.time()), "type": kind, "text": text})

    def save(self):
        atomic_write(self.path, {"history": list(self.history), "events": list(self.events),
                                 "mc_online": self.mc_online})


def atomic_write(path, data):
    """Escribe en un archivo temporal y lo renombra: la web nunca lee un JSON a medias."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = f"{path}.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)


# ===========================================================================
#  Bucle principal
# ===========================================================================
def collect(state, cache):
    now = int(time.time())
    mc = minecraft_status()
    cpu = cpu_percent()
    mem = memory()

    if time.time() - cache.get("world_t", 0) > WORLD_SIZE_EVERY:
        cache["world_size"] = world_size()
        cache["world_t"] = time.time()
    mc["world_size"] = cache.get("world_size")

    if state.mc_online is None:
        state.add_event("info", "Monitor iniciado")
    if mc["online"] != state.mc_online:
        if mc["online"]:
            state.add_event("up", "Servidor de Minecraft en línea")
        elif state.mc_online is not None:
            state.add_event("down", "Servidor de Minecraft caído o reiniciando")
        state.mc_online = mc["online"]

    tps = mc.get("tps")
    state.history.append({
        "t": now,
        "cpu": cpu,
        "ram": mem["percent"] if mem else None,
        "tps": tps[0] if tps else None,
        "players": mc.get("players_online", 0) if mc["online"] else 0,
    })

    return {
        "generated_at": now,
        "interval": CFG["INTERVAL"],
        "host": host_info(),
        "uptime": uptime_seconds(),
        "network": {"ip": CFG["SERVER_IP"] or local_ip(), "subnet": CFG["LAN_SUBNET"] or None,
                    "gateway": default_gateway()},
        "cpu": {"percent": cpu, "load": list(os.getloadavg()) if hasattr(os, "getloadavg") else None},
        "memory": mem,
        "temperatures": temperatures(),
        "disks": disks(),
        "services": services(),
        "minecraft": mc,
        "history": list(state.history),
        "events": list(state.events)[::-1],
    }


def main():
    ap = argparse.ArgumentParser(description="Recolector de estado del panel")
    ap.add_argument("--once", action="store_true", help="una sola lectura y salir")
    ap.add_argument("--stdout", action="store_true", help="mostrar el JSON en pantalla en vez de guardarlo")
    ap.add_argument("--rcon", metavar="COMANDO", help="enviar un comando a la consola de Minecraft")
    args = ap.parse_args()

    if args.rcon:
        rcon = open_rcon()
        if not rcon:
            sys.exit("RCON no está activado en server.properties")
        try:
            print(strip_colors(rcon.command(args.rcon)))
        finally:
            rcon.close()
        return

    state, cache = State(CFG["STATE"]), {}
    while True:
        started = time.time()
        try:
            data = collect(state, cache)
            if args.stdout:
                print(json.dumps(data, ensure_ascii=False, indent=2))
            else:
                atomic_write(CFG["OUTPUT"], data)
                state.save()
        except Exception as e:  # nunca dejar que un fallo puntual tumbe el monitor
            print(f"error en la lectura: {e}", file=sys.stderr, flush=True)
        if args.once:
            break
        time.sleep(max(1.0, CFG["INTERVAL"] - (time.time() - started)))


if __name__ == "__main__":
    main()
