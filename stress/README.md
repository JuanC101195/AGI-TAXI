# Pruebas de esfuerzo sobre AGI-TAXI — Proyecto Final Seminario Voz IP (UdeA, 2026)

Este directorio reúne la **Entrega 2** del Proyecto Final del Seminario de Voz IP: configuración de Asterisk para una prueba de carga (Load Testing) con [SIPp](https://sipp.readthedocs.io/) sobre el propio sistema AGI-TAXI, junto con los scripts de monitoreo, el runner del experimento y el documento (formato IEEE) listo para compilar.

> **Entrega 1** (descripción de técnicas y métricas) se entregó como `final voz ip.docx` y queda fuera de este repo. **Entrega 2** es todo lo contenido en esta carpeta.

## Estructura

```
stress/
├── README.md
├── asterisk/
│   ├── pjsip-stress.conf          # endpoint 6000 + AOR con 200 contactos
│   └── extensions-stress.conf     # contexto from-stress: 7000 (Echo) y 7100 (AGI)
├── sipp/
│   ├── uac-echo-no-rtp.xml        # escenario UAC con auth digest, sin RTP
│   └── uac-echo-rtp.xml           # escenario UAC con RTP G.711
├── scripts/
│   ├── install-tools.sh           # instala SIPp/sngrep/tshark/sysstat
│   ├── apply-config.sh            # añade #include a /etc/asterisk y recarga
│   ├── monitor.sh                 # captura CPU/mem/red/canales a CSV (1 Hz)
│   ├── run-load.sh                # orquesta la rampa de 7 escalones
│   └── plot.py                    # genera PNG desde el CSV de monitor.sh
├── latex/
│   └── entrega2.tex               # documento IEEE (compilable con pdflatex)
└── results/
    └── .gitkeep                   # las salidas de cada ejecución se guardan aquí
```

## Diseño del experimento

- **Tipo:** Load Testing (incremento progresivo, sin llevar a colapso).
- **Punto bajo prueba:** la propia VM AGI-TAXI (Asterisk 18+, Debian, 192.168.56.10:5060).
- **Comparativa pareada:** extensión `7000` (`Answer + Echo + Hangup`) vs `7100` (`Answer + AGI taxi_agi.py + Hangup`), con la misma señalización SIP/RTP, para aislar el costo del plano de negocio (consulta SQLite).
- **Endpoint dedicado** `6000` con auth digest (no llamadas anónimas).
- **Rampa** (`run-load.sh`): `10/25/50/100/150/200/300` concurrentes con CPS proporcional, 120 s por escalón y 10 s de enfriamiento.
- **Criterios de aceptación por escalón:** CPU sostenida < 80 %, llamadas OK ≥ 99 %, jitter < 30 ms, packet loss < 1 %.

## Procedimiento de ejecución

### 1. En la VM AGI-TAXI (servidor Asterisk)

```bash
cd stress/scripts
sudo ./apply-config.sh            # añade #include y recarga (dialplan + pjsip)
asterisk -rx 'pjsip show endpoint 6000'
asterisk -rx 'dialplan show from-stress'

# Monitoreo en sesión aparte (Ctrl+C al terminar)
./monitor.sh ../results/monitor.csv
```

> `apply-config.sh` no toca `pjsip.conf` ni `extensions.conf` originales: sólo añade dos líneas `#include` al final. Para revertir basta con eliminar esas dos líneas y recargar.

### 2. En la VM cliente SIPp (puede ser la misma VM)

```bash
cd stress/scripts
sudo ./install-tools.sh           # SIPp + sngrep + tshark + sysstat + matplotlib

# Escenario Echo (extensión 7000)
./run-load.sh

# Escenario AGI (extensión 7100)
SERVICE=7100 ./run-load.sh
```

### 3. Gráficas y documento

```bash
python3 plot.py ../results/monitor.csv ../results/
# Genera ../results/cpu_vs_channels.png y ../results/network.png

cd ../latex
# Copia las dos imágenes a esta carpeta (o ajusta el \includegraphics):
cp ../results/cpu_vs_channels.png placeholder_cpu.png
cp ../results/network.png          placeholder_net.png
pdflatex entrega2.tex && pdflatex entrega2.tex
```

## Convenciones y credenciales (sólo laboratorio)

| Recurso              | Valor                       |
|----------------------|-----------------------------|
| IP Asterisk          | `192.168.56.10:5060/UDP`    |
| Endpoint SIPp        | `6000`                      |
| Password SIPp        | `StressPass6000!`           |
| Extensión Echo       | `7000`                      |
| Extensión AGI taxi   | `7100`                      |
| Contexto dialplan    | `from-stress`               |

> Las credenciales son sólo para la red de laboratorio host-only de VirtualBox. **No usar en producción.**

## Evidencias a adjuntar a la Entrega 2

- `stress/results/<timestamp>/summary.csv` (totales por escalón).
- `stress/results/<timestamp>/step-*-screen.log` (pantalla final de SIPp).
- `stress/results/monitor.csv` (telemetría 1 Hz).
- `stress/results/cpu_vs_channels.png` y `network.png`.
- Capturas de `htop`, `asterisk -rx 'core show channels count'` y `sngrep` durante el escalón máximo aceptado.
- PDF compilado de `stress/latex/entrega2.tex`.
