#!/usr/bin/env bash
#
# apply-config.sh
#
# Aplica las extensiones de stress al Asterisk de la VM AGI-TAXI.
# Copia los includes a /etc/asterisk y recarga Asterisk sin reiniciar.
#
# Ejecutar como root en la VM Asterisk, desde la carpeta artifacts/asterisk:
#   sudo ./apply-config.sh
#
set -euo pipefail

ETC=/etc/asterisk
SRC="$(dirname "$0")/../asterisk"

cp -v "$SRC/pjsip-stress.conf"      "$ETC/pjsip-stress.conf"
cp -v "$SRC/extensions-stress.conf" "$ETC/extensions-stress.conf"

# Anade los #include si no existen
grep -q '#include "pjsip-stress.conf"'      "$ETC/pjsip.conf"      \
  || echo '#include "pjsip-stress.conf"'      >> "$ETC/pjsip.conf"
grep -q '#include "extensions-stress.conf"' "$ETC/extensions.conf" \
  || echo '#include "extensions-stress.conf"' >> "$ETC/extensions.conf"

chown -R asterisk:asterisk "$ETC"

asterisk -rx 'dialplan reload'
asterisk -rx 'pjsip reload'

echo
echo "Configuracion aplicada. Verifica con:"
echo "  asterisk -rx 'pjsip show endpoint 6000'"
echo "  asterisk -rx 'dialplan show from-stress'"
