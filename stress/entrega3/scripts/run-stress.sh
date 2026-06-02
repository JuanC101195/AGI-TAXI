#!/usr/bin/env bash
#
# run-stress.sh
#
# Prueba 2 (Entrega Final): STRESS TESTING
#
# A diferencia de la rampa de carga (Load Testing) ya ejecutada en la
# Entrega 2, esta prueba lleva el sistema MAS ALLA del punto de
# operacion esperado para encontrar el limite real (punto de quiebre).
# Se reutiliza el escenario SIPp y el endpoint 6000 ya configurados.
#
# Diferencia con run-load.sh:
#   - Empieza arriba del techo de Load Test (rampa 400..1500 conc)
#   - Tasas mas agresivas (60..200 cps)
#   - Acepta fallos: el "exito" aqui es encontrar donde se rompe
#
# Uso (en la VM AGI-TAXI):
#   cd ~/so-taxi-agi/stress/entrega3/scripts
#   chmod +x run-stress.sh
#   ./run-stress.sh
#
set -euo pipefail

REMOTE="${REMOTE:-127.0.0.1:5060}"
USER_AUTH="${USER_AUTH:-6000}"
PASS_AUTH="${PASS_AUTH:-StressPass6000!}"
SERVICE="${SERVICE:-7000}"
SCENARIO="${SCENARIO:-../../sipp/uac-echo-no-rtp.xml}"
DURATION_PER_STEP="${DURATION_PER_STEP:-90}"

# Escalones de stress: empieza donde termino Load Test (300) y sube.
# Format: "concurrent cps"
LEVELS=("400 60" "600 80" "800 100" "1000 130" "1200 160" "1500 200")

OUT_DIR="../results/stress-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT_DIR"
SUMMARY="$OUT_DIR/summary.csv"
echo "step,concurrent,cps,total_calls,successful,failed,retrans" > "$SUMMARY"

step=0
for level in "${LEVELS[@]}"; do
  step=$((step+1))
  read -r CONC CPS <<<"$level"
  echo "=== Stress Step $step | concurrent=$CONC cps=$CPS dur=${DURATION_PER_STEP}s ==="

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

  TOT=$(awk -F: '/Successful call/{gsub(/[^0-9]/,""); s+=$1} END{print s+0}'  "${LOG_PREFIX}-screen.log")
  FAIL=$(awk -F: '/Failed call/{gsub(/[^0-9]/,""); f+=$1} END{print f+0}'    "${LOG_PREFIX}-screen.log")
  RETR=$(awk -F: '/Retransmissions/{gsub(/[^0-9]/,""); r+=$1} END{print r+0}' "${LOG_PREFIX}-screen.log")
  TOTAL=$((TOT + FAIL))

  echo "$step,$CONC,$CPS,$TOTAL,$TOT,$FAIL,$RETR" >> "$SUMMARY"

  echo "    -> total=$TOTAL ok=$TOT fail=$FAIL retrans=$RETR"

  # Criterio de parada: si en este escalon falla mas del 20%,
  # consideramos que encontramos el punto de quiebre y paramos.
  if [ "$TOTAL" -gt 0 ] && [ "$FAIL" -gt $((TOTAL / 5)) ]; then
    echo "    *** Punto de quiebre detectado (failed > 20%). Deteniendo rampa. ***"
    break
  fi

  echo "    cooldown 15s"
  sleep 15
done

echo
echo "Resultados en: $OUT_DIR"
echo "Resumen     : $SUMMARY"
