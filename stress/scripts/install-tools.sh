#!/usr/bin/env bash
#
# install-tools.sh
#
# Instala las herramientas de stress testing en la VM CLIENTE (o en la
# misma VM Asterisk si se ejecuta todo en una sola maquina). Tambien
# instala sysstat/atop para el monitoreo en la VM servidor.
#
set -euo pipefail

sudo apt update
sudo apt install -y sip-tester sngrep tshark htop atop sysstat python3-matplotlib

echo
echo "Herramientas instaladas. Versiones:"
sipp -v | head -n 1
sngrep -V | head -n 1 || true
echo "sysstat: $(dpkg -s sysstat | awk -F': ' '/^Version/{print $2}')"
