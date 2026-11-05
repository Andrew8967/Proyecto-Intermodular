// =====================================================================
//  Panel de monitorización — lee data/status.json y pinta los datos.
//  status.json lo genera cada 10 s el script panel-status.py en el servidor.
//
//  Modo demo: si abres la página con ?demo (o como archivo local, sin
//  servidor), se generan datos de ejemplo para enseñarla en la presentación.
// =====================================================================

const STATUS_URL = 'data/status.json';
const REFRESH_MS = 5000;          // cada cuánto pregunto al servidor
const STALE_AFTER_S = 60;         // si los datos tienen más de 60 s, aviso

const params = new URLSearchParams(location.search);
const DEMO = params.has('demo') || location.protocol === 'file:';

let lastData = null;
let lastOk = 0;

// ---------- utilidades ----------
const $ = (id) => document.getElementById(id);

// escribo siempre con textContent (no innerHTML) para que un nombre de
// jugador raro no pueda meter HTML en la página
function setText(id, value) {
    const el = $(id);
    if (el) el.textContent = (value === null || value === undefined || value === '') ? '--' : value;
}

function fmtBytes(b) {
    if (b === null || b === undefined) return '--';
    const u = ['B', 'KB', 'MB', 'GB', 'TB'];
    let i = 0;
    while (b >= 1024 && i < u.length - 1) { b /= 1024; i++; }
    return `${b.toFixed(b >= 100 || i === 0 ? 0 : 1)} ${u[i]}`;
}

function fmtUptime(s) {
    if (s === null || s === undefined) return '--';
    const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
    return d > 0 ? `${d}d ${h}h ${m}m` : `${h}h ${m}m`;
}

function fmtAgo(seconds) {
    if (seconds < 5) return 'ahora mismo';
    if (seconds < 60) return `hace ${Math.round(seconds)} s`;
    if (seconds < 3600) return `hace ${Math.round(seconds / 60)} min`;
    return `hace ${Math.round(seconds / 3600)} h`;
}

function fmtTime(t) {
    return new Date(t * 1000).toLocaleString('es-ES', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
}

// nivel de alerta según el valor: ok / warn / bad
function level(value, warnAt, badAt, inverted = false) {
    if (value === null || value === undefined) return '';
    if (inverted) return value <= badAt ? 'bad' : value <= warnAt ? 'warn' : 'ok';
    return value >= badAt ? 'bad' : value >= warnAt ? 'warn' : 'ok';
}

function setLevel(id, lvl) {
    const el = $(id);
    if (!el) return;
    el.classList.remove('lvl-ok', 'lvl-warn', 'lvl-bad');
    if (lvl) el.classList.add(`lvl-${lvl}`);
}

function setBar(id, percent, lvl) {
    const el = $(id);
    if (!el) return;
    el.style.width = `${Math.max(0, Math.min(100, percent || 0))}%`;
    setLevel(id, lvl);
}

// mini gráfica SVG a partir de una lista de números
function sparkline(id, values, max, min = 0) {
    const svg = $(id);
    if (!svg) return;
    const pts = values.map((v, i) => [i, v]).filter(([, v]) => v !== null && v !== undefined);
    if (pts.length < 2) { svg.innerHTML = ''; return; }
    const n = values.length - 1 || 1;
    const top = max || Math.max(...pts.map(([, v]) => v), 1);
    const y = (v) => 58 - (Math.max(0, v - min) / (top - min || 1)) * 54;
    const coords = pts.map(([i, v]) => `${(i / n * 300).toFixed(1)},${y(v).toFixed(1)}`);
    svg.innerHTML =
        `<polyline class="spark-area" points="0,60 ${coords.join(' ')} 300,60"/>` +
        `<polyline class="spark-line" points="${coords.join(' ')}"/>`;
}

// ---------- pintar los datos ----------
function render(d) {
    const mc = d.minecraft || {};
    const history = d.history || [];

    // --- cabecera ---
    setText('uptime', fmtUptime(d.uptime));

    // --- minecraft ---
    const badge = $('mc-status');
    badge.textContent = mc.online ? 'EN LÍNEA' : 'APAGADO';
    badge.className = 'status-badge ' + (mc.online ? '' : 'badge-off');
    setText('mc-version', mc.version);
    setText('mc-motd', mc.online ? mc.motd : 'El servidor no responde (apagado, arrancando o reiniciando)');
    setText('mc-players', mc.online ? `${mc.players_online ?? (mc.players || []).length} / ${mc.max}` : '--');

    const tps = mc.tps ? mc.tps[0] : null;
    setText('mc-tps', tps !== null ? tps.toFixed(1) : '--');
    setLevel('mc-tps', level(tps, 18, 15, true));
    setText('mc-mspt', mc.mspt !== null && mc.mspt !== undefined ? mc.mspt.toFixed(1) : '--');
    setLevel('mc-mspt', level(mc.mspt, 40, 50));
    setText('mc-ping', mc.ping_ms !== undefined ? `${Math.round(mc.ping_ms)} ms` : '--');
    setText('mc-world', fmtBytes(mc.world_size));

    const list = $('mc-player-list');
    list.replaceChildren();
    const names = mc.online ? (mc.players || []) : [];
    if (names.length === 0) {
        const c = document.createElement('span');
        c.className = 'chip chip-empty';
        c.textContent = 'nadie conectado';
        list.appendChild(c);
    } else {
        names.forEach((n) => {
            const c = document.createElement('span');
            c.className = 'chip';
            c.textContent = n;
            list.appendChild(c);
        });
    }
    sparkline('spark-tps', history.map((h) => h.tps), 20, 10);   // eje de 10 a 20 TPS
    const ip = (d.network && d.network.ip) || location.hostname;
    setText('mc-address', `${ip}:25565`);

    // --- sistema ---
    const cpu = d.cpu ? d.cpu.percent : null;
    setText('cpu-value', cpu !== null ? `${cpu.toFixed(0)} %` : '--');
    setBar('cpu-bar', cpu, level(cpu, 70, 90));
    sparkline('spark-cpu', history.map((h) => h.cpu), 100);
    setText('cpu-load', d.cpu && d.cpu.load ? `carga media: ${d.cpu.load.map((x) => x.toFixed(2)).join(' · ')}` : 'carga: --');

    const mem = d.memory;
    setText('ram-value', mem ? `${mem.percent.toFixed(0)} %` : '--');
    setBar('ram-bar', mem && mem.percent, level(mem && mem.percent, 80, 92));
    sparkline('spark-ram', history.map((h) => h.ram), 100);
    setText('ram-sub', mem ? `${fmtBytes(mem.used)} de ${fmtBytes(mem.total)}` : '--');

    const t = d.temperatures ? d.temperatures.cpu : null;
    setText('temp-value', t !== null ? `${t.toFixed(0)} °C` : 'N/D');
    setBar('temp-bar', t !== null ? t : 0, level(t, 75, 90));
    setText('temp-sub', t !== null ? 'normal < 75 °C · alto > 90 °C' : 'sin sensores (normal en una máquina virtual)');

    const disks = $('disks');
    disks.replaceChildren();
    (d.disks || []).forEach((k) => {
        const row = document.createElement('div');
        row.className = 'disk';
        const name = document.createElement('span');
        name.className = 'disk-name';
        name.textContent = `${k.name} (${k.path})`;
        const info = document.createElement('span');
        info.className = 'disk-info';
        const bar = document.createElement('div');
        bar.className = 'bar';
        const fill = document.createElement('div');
        fill.className = 'bar-fill';
        if (k.total) {
            info.textContent = `${fmtBytes(k.used)} / ${fmtBytes(k.total)} (${k.percent} %)` + (k.mounted ? '' : ' · ¡no montado!');
            fill.style.width = `${k.percent}%`;
            fill.classList.add(`lvl-${level(k.percent, 80, 90)}`);
        } else {
            info.textContent = 'no conectado';
            row.classList.add('disk-missing');
        }
        bar.appendChild(fill);
        row.append(name, info, bar);
        disks.appendChild(row);
    });

    // --- servicios ---
    const sl = $('services');
    sl.replaceChildren();
    Object.entries(d.services || {}).forEach(([name, st]) => {
        const li = document.createElement('li');
        const dot = document.createElement('span');
        dot.className = 'dot ' + (st === 'active' ? 'dot-ok' : st === 'activating' ? 'dot-warn' : 'dot-bad');
        const n = document.createElement('span');
        n.textContent = name;
        const s = document.createElement('code');
        s.textContent = st === 'active' ? 'activo' : st === 'inactive' ? 'parado' : st === 'failed' ? 'fallo' : st;
        li.append(dot, n, s);
        sl.appendChild(li);
    });

    // --- eventos ---
    const el = $('events');
    el.replaceChildren();
    const events = d.events || [];
    if (events.length === 0) {
        const li = document.createElement('li');
        li.className = 'event-empty';
        li.textContent = 'sin eventos todavía';
        el.appendChild(li);
    }
    events.slice(0, 12).forEach((e) => {
        const li = document.createElement('li');
        li.className = `event event-${e.type}`;
        const time = document.createElement('code');
        time.textContent = fmtTime(e.t);
        const text = document.createElement('span');
        text.textContent = e.text;
        li.append(time, text);
        el.appendChild(li);
    });

    // --- hardware y red ---
    const h = d.host || {};
    setText('hw-host', h.hostname);
    setText('hw-cpu', h.cpu_model ? `${h.cpu_model} — ${h.cores} hilos` : null);
    setText('hw-ram', mem ? fmtBytes(mem.total) : null);
    setText('hw-os', h.os);
    setText('hw-kernel', h.kernel ? `${h.kernel} · ${h.arch}` : null);
    const virt = h.virtualization;
    setText('hw-virt', virt === 'lxc' ? 'Contenedor LXC en Proxmox VE'
        : virt === 'none' ? 'Ninguna (hardware real)'
        : virt ? `Máquina virtual (${virt})` : null);
    const net = d.network || {};
    setText('net-ip', net.ip);
    setText('net-subnet', net.subnet);
    setText('net-gw', net.gateway);
}

// estado de la conexión en la cabecera
function setConnection(kind, text) {
    const b = $('conn-badge');
    b.className = `conn-badge conn-${kind}`;
    b.textContent = text;
}

function tickClock() {
    if (!lastData) return;
    const age = Date.now() / 1000 - lastData.generated_at;
    setText('updated', `datos ${fmtAgo(age)}`);
    if (DEMO) return;
    const offlineFor = (Date.now() - lastOk) / 1000;
    if (offlineFor > REFRESH_MS / 1000 * 3) setConnection('bad', 'SIN CONEXIÓN');
    else if (age > STALE_AFTER_S) setConnection('warn', 'DATOS ANTIGUOS');
    else setConnection('ok', 'EN VIVO');
}

async function refresh() {
    if (DEMO) {
        lastData = demoData();
        render(lastData);
        setConnection('demo', 'MODO DEMO');
        tickClock();
        return;
    }
    try {
        const r = await fetch(`${STATUS_URL}?t=${Date.now()}`, { cache: 'no-store' });
        if (!r.ok) throw new Error(`HTTP ${r.status}`);
        lastData = await r.json();
        lastOk = Date.now();
        render(lastData);
    } catch (e) {
        console.warn('No se pudo leer status.json:', e);
        if (!lastData) setText('updated', 'no hay datos: ¿está activo panel-status?');
    }
    tickClock();
}

// =====================================================================
//  Datos de ejemplo para el modo demo (se mueven un poco cada vez)
// =====================================================================
const demo = { history: [], start: Date.now() / 1000 - 3 * 86400 - 5 * 3600 };
function demoData() {
    const now = Math.floor(Date.now() / 1000);
    const wave = (a, b, speed) => a + (b - a) * (0.5 + 0.5 * Math.sin(now / speed));
    const players = ['Andres', 'Alberto', 'Steve', 'Alex'].slice(0, Math.round(wave(1, 4, 40)));
    const cpu = wave(18, 46, 13) + Math.random() * 6;
    const ram = wave(41, 48, 50);
    const tps = Math.min(20, wave(18.6, 20.4, 23));
    if (demo.history.length === 0) {
        for (let i = 89; i > 0; i--) {
            demo.history.push({ t: now - i * 10, cpu: 20 + Math.random() * 25, ram: 42 + Math.random() * 5, tps: 19 + Math.random(), players: 2 });
        }
    }
    demo.history.push({ t: now, cpu, ram, tps, players: players.length });
    demo.history = demo.history.slice(-90);
    return {
        generated_at: now,
        uptime: now - demo.start,
        host: { hostname: 'mc-server', os: 'Debian GNU/Linux 13 (trixie)', kernel: '6.12.0-amd64', arch: 'x86_64',
                cpu_model: 'Intel(R) Core(TM) i3 (ejemplo)', cores: 4, virtualization: 'lxc' },
        network: { ip: '192.168.1.100', subnet: '192.168.1.0/24', gateway: '192.168.1.1' },
        cpu: { percent: cpu, load: [cpu / 40, cpu / 45, cpu / 50] },
        memory: { total: 16 * 1024 ** 3, used: 16 * 1024 ** 3 * ram / 100, percent: ram },
        temperatures: { cpu: wave(48, 61, 30) },
        disks: [
            { name: 'Disco del CT (SSD)', path: '/', mounted: true, total: 40e9, used: 6.2e9, percent: 15.5 },
            { name: 'Disco externo', path: '/mnt/externo', mounted: true, total: 1e12, used: 212e9, percent: 21.2 },
        ],
        services: { ssh: 'active', apache2: 'active', minecraft: 'active', fail2ban: 'active', 'panel-status': 'active', 'minecraft-backup.timer': 'active' },
        minecraft: { online: true, version: 'Paper 1.21.4', motd: 'Servidor Intermodular - 2 SMR', max: 10, players_online: players.length,
                     players, tps: [tps, 19.9, 19.9], mspt: wave(8, 24, 17), ping_ms: wave(1, 4, 9), world_size: 412 * 1024 ** 2 },
        history: demo.history,
        events: [
            { t: now - 3600, type: 'up', text: 'Servidor de Minecraft en línea' },
            { t: now - 3700, type: 'down', text: 'Servidor de Minecraft caído o reiniciando' },
            { t: now - 86400, type: 'up', text: 'Servidor de Minecraft en línea' },
            { t: now - 3 * 86400, type: 'info', text: 'Monitor iniciado' },
        ],
    };
}

// ---------- arranque ----------
refresh();
setInterval(refresh, REFRESH_MS);
setInterval(tickClock, 1000);
