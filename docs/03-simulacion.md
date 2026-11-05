# 03 · Entorno de simulación (antes de tener el mini PC)

Todo se prueba primero en una **máquina virtual Debian 13 x86_64** en el portátil. Como el mini PC también es x86_64, lo que funciona en la VM funciona igual en el servidor real.

**Equipo de desarrollo:** Windows 11 Home, Intel i7-1255U, 16 GB de RAM.

## Opción recomendada: VirtualBox

Es gratuito, funciona en Windows 11 Home y tiene interfaz gráfica (VMware Workstation Pro también es gratis para uso personal y sirve igual).

1. Descargar la ISO de **Debian 13 "Trixie" netinst amd64** desde debian.org.
2. Crear la VM:
   - 2 CPU y 4 GB de RAM (con 16 GB en el portátil va sobrado).
   - Disco de 30 GB.
3. Instalar Debian (ver [04-instalacion.md](04-instalacion.md)). En "Selección de programas" marcar solo **servidor SSH** y **utilidades estándar**.
4. **Red.** Dos formas:
   - **NAT con reenvío de puertos** (la más sencilla). En Configuración → Red → Avanzadas → Reenvío de puertos:

     | Nombre | Puerto anfitrión | Puerto invitado |
     |---|---|---|
     | ssh | 2222 | 22 |
     | web | 8080 | 80 |
     | minecraft | 25565 | 25565 |

     En este modo, en `scripts/config.env` pon `SIMULACION_NAT="si"`: el tráfico llega a la VM desde `10.0.2.2` y el firewall tiene que permitirlo.
   - **Adaptador puente** (más realista). La VM coge una IP de tu router, como un equipo más de la LAN. Con este modo no hace falta `SIMULACION_NAT`.

Desde Windows, con NAT:
```powershell
ssh -p 2222 tu_usuario@localhost       # terminal del servidor
start http://localhost:8080            # panel web
# Minecraft → Multijugador → localhost:25565
```

## Opción alternativa: QEMU

Si sigues con QEMU (es lo que se usó en la v1), **activa la aceleración**: sin ella QEMU emula la CPU por software y va muy lento.

1. Activar en Windows: *Panel de control → Programas → Activar o desactivar características → **Plataforma del hipervisor de Windows***, y reiniciar.
2. Arrancar la VM con `-accel whpx`:

```powershell
qemu-system-x86_64 -accel whpx -cpu max -smp 2 -m 4096 `
  -drive file=debian13.qcow2,format=qcow2 `
  -nic user,model=virtio-net-pci,hostfwd=tcp::2222-:22,hostfwd=tcp::8080-:80,hostfwd=tcp::25565-:25565
```

Si `whpx` da error, prueba `-accel whpx,kernel-irqchip=off`.

## Probar Proxmox en la VM (opcional)

Proxmox se puede instalar dentro de VirtualBox con **virtualización anidada**, para practicar antes de tener el mini PC:

```powershell
VBoxManage modifyvm "Proxmox" --nested-hw-virt on
```

Va lento y no es necesario. Lo importante es probar los scripts en Debian 13.

## Qué se puede probar en la VM y qué no

| Se puede probar | Solo en el hardware real |
|---|---|
| Todos los scripts (`01` a `04`) | Temperaturas reales (en la VM el panel pone "N/D") |
| Minecraft conectándose desde el portátil | Rendimiento real (TPS con varios jugadores) |
| El panel con datos en vivo | Consumo eléctrico |
| UFW, SSH con clave, fail2ban | Disco externo por USB (se puede simular con un disco virtual extra) |
| Copias de seguridad y restauración | Arranque automático tras un corte de luz |
