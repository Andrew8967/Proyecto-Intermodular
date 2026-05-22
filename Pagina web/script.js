// guardo cuando se cargo la pagina para calcular el tiempo
const startTime = Date.now();

// esta funcion calcula cuanto tiempo lleva abierta la pagina y lo muestra
function updateUptime() {
    const elapsed = Math.floor((Date.now() - startTime) / 1000);
    // separo en horas minutos y segundos
    const h = Math.floor(elapsed / 3600).toString().padStart(2, '0');
    const m = Math.floor((elapsed % 3600) / 60).toString().padStart(2, '0');
    const s = (elapsed % 60).toString().padStart(2, '0');
    document.getElementById('uptime').textContent = `${h}:${m}:${s}`;
}

// actualizo el contador cada segundo
setInterval(updateUptime, 1000);
updateUptime();

// cuando carga la pagina hago que las tarjetas aparezcan poco a poco
document.addEventListener('DOMContentLoaded', () => {
    const cards = document.querySelectorAll('.service-card');
    cards.forEach((card, i) => {
        // empiezan invisibles y un poco mas abajo
        card.style.opacity = '0';
        card.style.transform = 'translateY(16px)';
        card.style.transition = `opacity 0.4s ease ${i * 0.1}s, transform 0.4s ease ${i * 0.1}s`;
        // despues de un momento aparecen en su sitio
        setTimeout(() => {
            card.style.opacity = '1';
            card.style.transform = 'translateY(0)';
        }, 50);
    });
});