#!/usr/bin/env bash
#
# run-load.sh
#
# Orquesta la prueba de Load Testing. Ejecuta SIPp por escalones de
# concurrencia y deja un CSV consolidado con las estadisticas finales
# de cada escalon. Se ejecuta en la VM CLIENTE (la que tiene SIPp).
#
# Requisitos:
#   - sipp instalado (sudo apt install sip-tester)
#   - Conectividad UDP hacia 192.168.56.10:5060
#   - monitor.sh corriendo en la VM Asterisk
#
# Uso:
#   ./run-load.sh
#
set -euo pipefail

REMOTE="${REMOTE:-192.168.56.10:5060}"
USER_AUTH="${USER_AUTH:-6000}"
PASS_AUTH="${PASS_AUTH:-StressPass6000!}"
SERVICE="${SERVICE:-7000}"               # 7000=echo, 7100=AGI
SCENARIO="${SCENARIO:-../sipp/uac-echo-no-rtp.xml}"
DURATION_PER_STEP="${DURATION_PER_STEP:-120}"   # segundos por escalon

# Escalones de concurrencia y tasa de llamadas por segundo (CPS).
# Ajustar segun la VM disponible.
LEVELS=("10 5" "25 10" "50 15" "100 20" "150 25" "200 30" "300 40")

OUT_DIR="../results/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT_DIR"
SUMMARY="$OUT_DIR/summary.csv"
echo "step,concurrent,cps,total_calls,successful,failed,retrans,avg_rt_ms" > "$SUMMARY"

step=0
for level in "${LEVELS[@]}"; do
  step=$((step+1))
  read -r CONC CPS <<<"$level"
  echo "=== Step $step | concurrent=$CONC cps=$CPS dur=${DURATION_PER_STEP}s ==="

  LOG_PREFIX="$OUT_DIR/step-${step}-c${CONC}"
  CALL_TARGET=$((CPS * DURATION_PER_STEP))

  sipp -sf "$SCENARIO" -s "$SERVICE" "$REMOTE" \
       -au "$USER_AUTH" -ap "$PASS_AUTH" \
       -l "$CONC" -r "$CPS" -m "$CALL_TARGET" \
       -trace_err -trace_stat -trace_screen \
       -screen_file "${LOG_PREFIX}-screen.log" \
       -error_file "${LOG_PREFIX}-error.log" \
       -stf "${LOG_PREFIX}-stat.csv" \
       -fd 1 \
       2> "${LOG_PREFIX}-stderr.log" || true

  # Extrae totales de la pantalla final de SIPp
  TOT=$(awk -F: '/Successful call/{gsub(/[^0-9]/,""); s+=$1} END{print s+0}'  "${LOG_PREFIX}-screen.log")
  FAIL=$(awk -F: '/Failed call/{gsub(/[^0-9]/,""); f+=$1} END{print f+0}'    "${LOG_PREFIX}-screen.log")
  RETR=$(awk -F: '/Retransmissions/{gsub(/[^0-9]/,""); r+=$1} END{print r+0}' "${LOG_PREFIX}-screen.log")
  TOTAL=$((TOT + FAIL))

  echo "$step,$CONC,$CPS,$TOTAL,$TOT,$FAIL,$RETR," >> "$SUMMARY"

  echo "    -> total=$TOTAL ok=$TOT fail=$FAIL retrans=$RETR"
  echo "    cooldown 10s"
  sleep 10
done

echo
echo "Resultados en: $OUT_DIR"
echo "Resumen     : $SUMMARY"
