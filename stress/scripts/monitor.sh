#!/usr/bin/env bash
#
# monitor.sh
#
# Captura metricas del sistema y de Asterisk cada segundo y las escribe en
# un CSV unificado. Pensado para correr en la VM Asterisk EN PARALELO con
# la prueba SIPp. Detener con Ctrl+C; el archivo CSV queda completo.
#
# Uso:
#   ./monitor.sh resultados/run-001.csv
#
# Columnas:
#   timestamp,cpu_usr,cpu_sys,cpu_iow,cpu_idle,mem_used_mb,mem_free_mb,
#   net_rx_kbps,net_tx_kbps,ast_channels,ast_endpoints_online
#
set -euo pipefail

OUT="${1:-monitor.csv}"
IFACE="${IFACE:-enp0s8}"   # interfaz host-only de VirtualBox por defecto

echo "timestamp,cpu_usr,cpu_sys,cpu_iow,cpu_idle,mem_used_mb,mem_free_mb,net_rx_kbps,net_tx_kbps,ast_channels,ast_endpoints_online" > "$OUT"

# Lecturas previas de red para calcular el delta
rx_prev=$(cat /sys/class/net/"$IFACE"/statistics/rx_bytes 2>/dev/null || echo 0)
tx_prev=$(cat /sys/class/net/"$IFACE"/statistics/tx_bytes 2>/dev/null || echo 0)

while true; do
  ts=$(date +%s)

  # CPU desde /proc/stat (delta de 1s gracias al sleep al final)
  read -r cpu user nice sys idle iowait irq softirq steal _ < /proc/stat
  total1=$((user+nice+sys+idle+iowait+irq+softirq+steal))
  idle1=$idle
  iow1=$iowait
  usr1=$user
  sys1=$sys

  sleep 1

  read -r cpu user nice sys idle iowait irq softirq steal _ < /proc/stat
  total2=$((user+nice+sys+idle+iowait+irq+softirq+steal))
  d_total=$((total2-total1))
  d_idle=$((idle-idle1))
  d_iow=$((iowait-iow1))
  d_usr=$((user-usr1))
  d_sys=$((sys-sys1))

  if [ "$d_total" -gt 0 ]; then
    cpu_usr=$(awk "BEGIN{printf \"%.1f\", 100*$d_usr/$d_total}")
    cpu_sys=$(awk "BEGIN{printf \"%.1f\", 100*$d_sys/$d_total}")
    cpu_iow=$(awk "BEGIN{printf \"%.1f\", 100*$d_iow/$d_total}")
    cpu_idle=$(awk "BEGIN{printf \"%.1f\", 100*$d_idle/$d_total}")
  else
    cpu_usr=0; cpu_sys=0; cpu_iow=0; cpu_idle=0
  fi

  # Memoria en MB
  mem_used=$(awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{printf "%.0f", (t-a)/1024}' /proc/meminfo)
  mem_free=$(awk '/MemAvailable/{printf "%.0f", $2/1024}' /proc/meminfo)

  # Trafico de red en kbps (delta 1s)
  rx_now=$(cat /sys/class/net/"$IFACE"/statistics/rx_bytes 2>/dev/null || echo 0)
  tx_now=$(cat /sys/class/net/"$IFACE"/statistics/tx_bytes 2>/dev/null || echo 0)
  net_rx_kbps=$(( (rx_now - rx_prev) * 8 / 1000 ))
  net_tx_kbps=$(( (tx_now - tx_prev) * 8 / 1000 ))
  rx_prev=$rx_now
  tx_prev=$tx_now

  # Estado de Asterisk
  ast_channels=$(asterisk -rx "core show channels count" 2>/dev/null \
                  | awk '/active channel/ {print $1; exit}')
  ast_channels="${ast_channels:-0}"

  ast_endpoints_online=$(asterisk -rx "pjsip show endpoints" 2>/dev/null \
                  | awk '/Endpoint:/ && /Not in use|In use|Busy/ {c++} END{print c+0}')

  echo "$ts,$cpu_usr,$cpu_sys,$cpu_iow,$cpu_idle,$mem_used,$mem_free,$net_rx_kbps,$net_tx_kbps,$ast_channels,$ast_endpoints_online" >> "$OUT"
done
