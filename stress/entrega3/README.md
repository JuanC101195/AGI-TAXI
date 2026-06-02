# Entrega Final (junio 7) — Tres pruebas de stress + informe consolidado

Esta carpeta extiende [`stress/`](../README.md) con las **dos pruebas adicionales** que pide la Entrega Final del Seminario de Voz IP, manteniendo la trazabilidad con [Entrega 2](../latex/entrega2.tex) (Load Testing) y reutilizando la configuración Asterisk ya activa.

## Tres pruebas aplicadas en el proyecto

| # | Técnica (`final voz ip.docx`) | Dónde | Estado |
|---|---|---|---|
| 1 | **Load Testing** — incremento progresivo hasta el nivel esperado | [Entrega 2](../README.md), rampa 10→300 conc | ✅ 100% éxito |
| 2 | **Stress Testing** — más allá del límite normal hasta romper | `entrega3/scripts/run-stress.sh`, rampa 400→1500 conc | A ejecutar |
| 3 | **Spike Testing** — picos súbitos de tráfico | `entrega3/scripts/run-spike.sh`, 10→150 cps→10 | A ejecutar |

## Estructura

```
entrega3/
├── README.md
├── scripts/
│   ├── run-stress.sh        # rampa extendida buscando punto de quiebre
│   ├── run-spike.sh         # pico súbito 30s + recuperación
│   └── run-all.sh           # orquesta las dos con monitoreo en background
├── results/                 # CSVs + logs por escalón/fase
└── latex/
    └── informe_final.tex    # consolidación Entrega 1 + 2 + 3 (pendiente)
```

## Cómo ejecutar (en la VM AGI-TAXI)

Una sola línea desde SSH:

```bash
cd ~/so-taxi-agi
git pull
cd stress/entrega3/scripts
chmod +x *.sh
./run-all.sh
```

`run-all.sh` ejecuta secuencialmente:

1. **Monitor** en background → `../results/monitor-stress.csv`
2. **Stress Test**: rampa 400 → 600 → 800 → 1000 → 1200 → 1500 conc. Se detiene automáticamente cuando el porcentaje de fallos pase del 20% (punto de quiebre detectado).
3. **Reposo 20s**.
4. **Monitor** en background → `../results/monitor-spike.csv`
5. **Spike Test**: 30s baseline (10 cps) → 30s pico (150 cps) → 30s recovery (10 cps).
6. Pásame los `summary.csv` que muestre y los picos de CPU/canales/mem.

Tiempo total aproximado: 12–18 min en VM.

## Evidencias esperadas tras ejecutar

- `results/stress-<timestamp>/summary.csv` con escalón donde se rompe.
- `results/spike-<timestamp>/summary.csv` con las tres fases (baseline / spike / recovery).
- `results/monitor-stress.csv` y `monitor-spike.csv` con telemetría 1 Hz.
- `step-N-cX-screen.log` por cada escalón de SIPp (igual que Entrega 2).

## Reutilización de Entrega 2

- **Configuración Asterisk**: ya activa en la VM (`pjsip-stress.conf` + `extensions-stress.conf`). No se aplica nada nuevo.
- **Escenario SIPp**: `../sipp/uac-echo-no-rtp.xml` reutilizado en ambas pruebas.
- **Monitor**: `../scripts/monitor.sh` reutilizado.
- **Endpoint**: `6000` / `StressPass6000!` reutilizado.
