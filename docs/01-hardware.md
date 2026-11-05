# 01 · Hardware: elección y compra del mini PC

## Por qué se descartó la Raspberry Pi 5

La primera versión del proyecto ([documentación v1](archivo/documentacion-v1-raspberry-pi5.pdf)) usaba una Raspberry Pi 5 de 8 GB. Se cambió a un **mini PC x86_64** por estos motivos:

| Motivo | Explicación |
|---|---|
| **Misma arquitectura en simulación y en real** | La Raspberry es ARM64. En el portátil (x86_64) solo se puede probar ARM **emulando** la CPU, que es muy lento. Con un mini PC x86 la máquina virtual de pruebas es *idéntica* al servidor final: mismos paquetes, mismos comandos y mismos scripts. |
| **Más potencia por el mismo dinero** | Un i3 o un Intel N-series tiene mejor rendimiento por núcleo que el Cortex-A76 de la Pi. Para Minecraft eso es lo más importante, porque el servidor procesa el mundo principalmente en un solo hilo. |
| **16 GB de RAM** | Hay sitio para Minecraft, el panel y el homelab de Alberto a la vez. La Pi 5 se queda en 8 GB como máximo. |
| **Todo incluido** | La Pi necesita comprar aparte la fuente, la caja, la refrigeración y el adaptador NVMe. El mini PC trae todo. |
| **Virtualización** | El mini PC lleva Proxmox VE: Minecraft va en un contenedor y el homelab de Alberto en otro, aislados ([02-arquitectura.md](02-arquitectura.md)). Proxmox oficial solo existe para x86_64: en la Raspberry habría que usar ports no oficiales. |

> El argumento **no** es que Minecraft no funcione en ARM: PaperMC es Java y funciona en cualquier arquitectura. El argumento es la simulación fiel, la potencia y la flexibilidad.

**Contrapartida:** el mini PC consume más (unos 10-25 W frente a 5-12 W). Encendido 24 horas al día, eso son 3-4 € de luz al mes como mucho.

## Requisitos mínimos para la compra

| Componente | Mínimo | Ideal |
|---|---|---|
| CPU | Intel x86_64 de 4 núcleos (i3 de 8ª a 10ª gen., N100/N150) | i3 de 11ª o 12ª gen. (i3-1115G4, i3-1215U) o N150/N200 |
| RAM | **16 GB** (DDR4 o DDR5) | 16 GB en **dos módulos** (doble canal), si el modelo lo permite |
| Almacenamiento | **SSD de 128 GB** (sistema y Minecraft) | NVMe de 256 GB |
| Almacenamiento extra | **Disco externo de 1-2 TB** por USB 3 | Bahía SATA de 2,5" interna si el modelo la tiene |
| Red | Ethernet Gigabit | Tarjeta de red Intel (mejor soporte en Linux que Realtek) |
| Puertos | 2 o más USB 3.0 (para el disco externo) | USB-C o 2.5GbE como extra |

### Checklist antes de pagar (AliExpress / Temu)

- [ ] El anuncio dice el **modelo exacto de CPU**. Si pone solo "Intel Core" o "i3" sin número, desconfía.
- [ ] Viene **con RAM y SSD incluidos**. Si pone "barebone", llega sin ellos.
- [ ] Trae una **fuente con enchufe europeo (EU)**.
- [ ] Sale de un **almacén en España o la UE**: llega antes y no hay aduana.
- [ ] El **IVA está incluido** en el precio final.
- [ ] Tiene **Ethernet** (algunos modelos muy baratos solo traen WiFi).
- [ ] Opiniones con fotos, de otros compradores, con el mismo modelo.
- [ ] Evita los "i7 a 90 €": suelen ser CPU de 4ª a 6ª generación, que gastan mucho y no rinden más.

## Presupuesto aproximado

| Componente | Detalle | Precio aprox. |
|---|---|---|
| Mini PC | x86_64, 16 GB RAM, SSD 128 GB, Ethernet (AliExpress/Temu) | **~150 €** |
| Disco externo 1-2 TB | Aportado por Alberto o por mí (reutilizado) | 0 € |
| Cable Ethernet | Cat 6, 2-3 m | ~5 € (o reutilizado) |
| **Total** | | **~150 €** |

Comparado con la v1 (Raspberry Pi 5 con accesorios: ~207-300 €), sale **más barato y más potente**.

## Una vez comprado

1. Actualizar la BIOS **solo** si el fabricante publica una versión oficial.
2. En la BIOS:
   - Activar **"Restore on AC Power Loss"** (o "Power On"): el servidor se enciende solo si se va la luz.
   - Activar **VT-x / VT-d** (Proxmox lo necesita para las máquinas virtuales de Alberto).
   - Desactivar **Secure Boot** si da problemas al instalar Debian o Proxmox.
3. Anotar el modelo exacto, los núcleos, la RAM y los discos (`lscpu`, `free -h`, `lsblk`) para la documentación.
4. Medir el consumo con un enchufe medidor en reposo y con Minecraft en marcha (es un dato bueno para la memoria).
