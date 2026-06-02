#!/usr/bin/env bash
#
# run-spike.sh
#
# Prueba 3 (Entrega Final): SPIKE TESTING
#
# Genera un patron de trafico que simula la situacion realista de
# "hora pico" en el servicio AGI-TAXI: el sistema esta operando con
# trafico bajo y sostenido, recibe un PICO SUBITO de llamadas
# (por ejemplo: lluvia repentina, evento masivo), y luego vuelve al
# nivel base.
#
# Tres fases sin pausa entre ellas:
#   Fase A - Baseline   : 30s a  10 cps (carga base)
#   Fase B - SPIKE      : 30s a 150 cps (15x el baseline en 1 segundo)
#   Fase C - Recovery   : 30s a  10 cps (vuelta al baseline)
#
# Se reutiliza el escenario uac-echo-no-rtp.xml y el endpoint 6000.
#
# Uso (en la VM AGI-TAXI):
#   cd ~/so-taxi-agi/stress/entrega3/scripts
#   chmod +x run-spike.sh
#   ./run-spike.sh
#
set -euo pipefail

REMOTE="${REMOTE:-127.0.0.1:5060}"
USER_AUTH="${USER_AUTH:-6000}"
PASS_AUTH="${PASS_AUTH:-StressPass6000!}"
SERVICE="${SERVICE:-7000}"
SCENARIO="${SCENARIO:-../../sipp/uac-echo-no-rtp.xml}"

OUT_DIR="../results/spike-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT_DIR"
SUMMARY="$OUT_DIR/summary.csv"
echo "fase,duration_s,cps,concurrent_limit,total_calls,successful,failed,retrans" > "$SUMMARY"

run_phase() {
  local PHASE="$1"     # A, B, C
  local NAME="$2"      # baseline, spike, recovery
  local DUR="$3"       # seconds
  local CPS="$4"
  local CONC="$5"

  local CALLS=$((CPS * DUR))
  local LOG_PREFIX="$OUT_DIR/phase-${PHASE}-${NAME}"

  echo "=== Fase $PHASE ($NAME) | cps=$CPS conc=$CONC dur=${DUR}s calls=$CALLS ==="

  sipp -sf "$SCENARIO" -s "$SERVICE" "$REMOTE" \
       -au "$USER_AUTH" -ap "$PASS_AUTH" \
       -l "$CONC" -r "$CPS" -m "$CALLS" \
       -trace_err -trace_stat -trace_screen \
       -screen_file "${LOG_PREFIX}-screen.log" \
       -error_file "${LOG_PREFIX}-error.log" \
       -stf "${LOG_PREFIX}-stat.csv" \
       -fd 1 \
       2> "${LOG_PREFIX}-stderr.log" || true

  local TOT=$(awk -F: '/Successful call/{gsub(/[^0-9]/,""); s+=$1} END{print s+0}'  "${LOG_PREFIX}-screen.log")
  local FAIL=$(awk -F: '/Failed call/{gsub(/[^0-9]/,""); f+=$1} END{print f+0}'    "${LOG_PREFIX}-screen.log")
  local RETR=$(awk -F: '/Retransmissions/{gsub(/[^0-9]/,""); r+=$1} END{print r+0}' "${LOG_PREFIX}-screen.log")
  local TOTAL=$((TOT + FAIL))

  echo "$NAME,$DUR,$CPS,$CONC,$TOTAL,$TOT,$FAIL,$RETR" >> "$SUMMARY"
  echo "    -> total=$TOTAL ok=$TOT fail=$FAIL retrans=$RETR"
}

# Fase A: baseline tranquilo 30s @ 10 cps
run_phase "A" "baseline" 30 10  50

# Fase B: PICO subito 30s @ 150 cps (15x el baseline)
run_phase "B" "spike"    30 150 300

# Fase C: recovery 30s @ 10 cps
run_phase "C" "recovery" 30 10  50

echo
echo "Resultados en: $OUT_DIR"
echo "Resumen     : $SUMMARY"
echo
echo "Para visualizar el efecto del pico, comparar las tres lineas del"
echo "summary.csv: el patron esperado es OK=100% en A y C, y un dip en B"
echo "(o exito completo si el sistema absorbe el pico)."
