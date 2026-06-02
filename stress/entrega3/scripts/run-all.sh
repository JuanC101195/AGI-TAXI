#!/usr/bin/env bash
#
# run-all.sh
#
# Orquesta las DOS nuevas pruebas de la Entrega Final (Stress + Spike)
# con monitoreo de telemetria en background, en un solo bloque para
# minimizar interaccion manual.
#
# Reutiliza el monitor.sh de la Entrega 2.
#
# Uso (en la VM AGI-TAXI):
#   cd ~/so-taxi-agi/stress/entrega3/scripts
#   chmod +x *.sh
#   ./run-all.sh
#
set -euo pipefail

MONITOR=../../scripts/monitor.sh
RESULTS_DIR=../results

# Cleanup defensivo
sudo pkill -f monitor.sh 2>/dev/null || true
sleep 1
sudo -v

IFACE=$(ip -br addr | awk '/192.168.56/ {print $1; exit}')
echo "Interfaz host-only: $IFACE"

# -------- PRUEBA 2: STRESS TESTING --------
echo
echo "================================================================"
echo "  PRUEBA 2: STRESS TESTING (rampa extendida 400..1500 conc)    "
echo "================================================================"

sudo nohup env LC_ALL=C IFACE=$IFACE "$MONITOR" "$RESULTS_DIR/monitor-stress.csv" \
     > "$RESULTS_DIR/monitor-stress.log" 2>&1 &
sleep 3
head -2 "$RESULTS_DIR/monitor-stress.csv"

./run-stress.sh

sudo pkill -f monitor.sh 2>/dev/null || true
sleep 2
echo "--- Picos durante Stress Test ---"
awk -F, 'NR>1 {c=$2+$3+$4; if(c>maxcpu)maxcpu=c; if($10>maxch)maxch=$10; if($6>maxmem)maxmem=$6} END{printf "CPU max: %.1f%%\nCanales max: %d\nMem max: %d MB\n", maxcpu, maxch, maxmem}' "$RESULTS_DIR/monitor-stress.csv"

echo "Reposo 20 segundos antes de la siguiente prueba..."
sleep 20

# -------- PRUEBA 3: SPIKE TESTING --------
echo
echo "================================================================"
echo "  PRUEBA 3: SPIKE TESTING (10 -> 150 cps -> 10)                 "
echo "================================================================"

sudo nohup env LC_ALL=C IFACE=$IFACE "$MONITOR" "$RESULTS_DIR/monitor-spike.csv" \
     > "$RESULTS_DIR/monitor-spike.log" 2>&1 &
sleep 3
head -2 "$RESULTS_DIR/monitor-spike.csv"

./run-spike.sh

sudo pkill -f monitor.sh 2>/dev/null || true
sleep 2
echo "--- Picos durante Spike Test ---"
awk -F, 'NR>1 {c=$2+$3+$4; if(c>maxcpu)maxcpu=c; if($10>maxch)maxch=$10; if($6>maxmem)maxmem=$6} END{printf "CPU max: %.1f%%\nCanales max: %d\nMem max: %d MB\n", maxcpu, maxch, maxmem}' "$RESULTS_DIR/monitor-spike.csv"

echo
echo "================================================================"
echo "  RESULTADOS"
echo "================================================================"
ls -la "$RESULTS_DIR"
echo
echo "Summaries:"
for f in $(ls "$RESULTS_DIR"/stress-*/summary.csv "$RESULTS_DIR"/spike-*/summary.csv 2>/dev/null); do
  echo "--- $f ---"
  cat "$f"
done
