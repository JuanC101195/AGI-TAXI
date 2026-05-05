#!/usr/bin/env bash
#
# instalar.sh - Despliegue del AGI de taxis en una VM Debian con Asterisk
# =========================================================================
#
# Requisitos:
#   - VM Debian 12 con red configurada (preferiblemente Adaptador Puente).
#   - Correr como root (con sudo).
#   - Tener este script y los demas archivos del proyecto en la misma carpeta.
#
# Lo que hace, en orden:
#   1. Instala Asterisk + Python + espeak + sox.
#   2. Copia taxi_agi.py e init_db.py a /var/lib/asterisk/agi-bin/.
#   3. Inicializa la BD SQLite con datos demo.
#   4. Genera los audios en espanol con espeak (8kHz mono PCM, formato Asterisk).
#   5. Copia extensions.conf y pjsip.conf a /etc/asterisk/.
#   6. Ajusta permisos para el usuario asterisk.
#   7. Reinicia el servicio Asterisk.
#
# Uso:
#   chmod +x instalar.sh
#   sudo ./instalar.sh

set -euo pipefail

# -------------------------------------------------------------------------
#  Helpers de output
# -------------------------------------------------------------------------
verde="\033[1;32m"
amarillo="\033[1;33m"
rojo="\033[1;31m"
nc="\033[0m"

paso()   { echo -e "${verde}==> $*${nc}"; }
aviso()  { echo -e "${amarillo}!! $*${nc}"; }
error()  { echo -e "${rojo}xx $*${nc}"; }

if [[ $EUID -ne 0 ]]; then
    error "Este script tiene que correr como root. Usar: sudo ./instalar.sh"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -------------------------------------------------------------------------
#  1. Dependencias
# -------------------------------------------------------------------------
paso "Instalando paquetes (asterisk, python3, espeak, sox)..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    asterisk \
    asterisk-modules \
    python3 \
    espeak \
    sox

# -------------------------------------------------------------------------
#  2. Copiar scripts AGI
# -------------------------------------------------------------------------
paso "Copiando scripts AGI a /var/lib/asterisk/agi-bin/..."
mkdir -p /var/lib/asterisk/agi-bin
cp "$SCRIPT_DIR/taxi_agi.py" /var/lib/asterisk/agi-bin/
cp "$SCRIPT_DIR/init_db.py"  /var/lib/asterisk/agi-bin/
chmod +x /var/lib/asterisk/agi-bin/taxi_agi.py
chmod +x /var/lib/asterisk/agi-bin/init_db.py

# -------------------------------------------------------------------------
#  3. Inicializar BD SQLite
# -------------------------------------------------------------------------
paso "Inicializando BD con datos demo..."
python3 /var/lib/asterisk/agi-bin/init_db.py

# -------------------------------------------------------------------------
#  4. Generar audios en espanol
# -------------------------------------------------------------------------
paso "Generando audios en espanol con espeak (puede tardar 30 segundos)..."
SOUNDS_DIR=/var/lib/asterisk/sounds/custom/taxi
mkdir -p "$SOUNDS_DIR"

generate_audio() {
    local file="$1"
    local text="$2"
    local tmp="/tmp/${file}_raw.wav"

    # espeak genera 22050 Hz por defecto; sox lo lleva a 8000 Hz mono PCM
    # 16-bit, que es el formato esperado por Asterisk para .wav genericos.
    espeak -v es -s 140 -p 50 -w "$tmp" "$text"
    sox "$tmp" -r 8000 -c 1 -b 16 "$SOUNDS_DIR/${file}.wav"
    rm -f "$tmp"
}

generate_audio "bienvenida"        "Bienvenido al servicio de taxis. Por favor marque su numero de documento seguido de la tecla numeral."
generate_audio "pedir_zip"         "Marque el codigo postal del area de recogida seguido de la tecla numeral."
generate_audio "taxi_disponible"   "Tenemos un taxi disponible. La placa es:"
generate_audio "no_disponible"     "Lo sentimos. No hay taxis disponibles en esa zona en este momento. Por favor intente mas tarde."
generate_audio "confirmar"         "Marque uno para confirmar la reserva, o dos para cancelar."
generate_audio "confirmada"        "Su reserva ha sido confirmada. El taxi llegara en breve. Gracias."
generate_audio "cancelada"         "Su reserva ha sido cancelada."
generate_audio "despedida"         "Gracias por usar nuestro servicio. Hasta pronto."
generate_audio "no_input"          "No recibimos su entrada. La llamada se cerrara."

# -------------------------------------------------------------------------
#  5. Copiar configs Asterisk
# -------------------------------------------------------------------------
paso "Copiando configs a /etc/asterisk/..."
cp "$SCRIPT_DIR/extensions.conf" /etc/asterisk/extensions.conf
cp "$SCRIPT_DIR/pjsip.conf"      /etc/asterisk/pjsip.conf

# -------------------------------------------------------------------------
#  6. Permisos
# -------------------------------------------------------------------------
paso "Ajustando permisos para el usuario asterisk..."
chown -R asterisk:asterisk /var/lib/asterisk/agi-bin
chown -R asterisk:asterisk "$SOUNDS_DIR"
chown asterisk:asterisk    /etc/asterisk/extensions.conf
chown asterisk:asterisk    /etc/asterisk/pjsip.conf

# Asterisk corre como user 'asterisk' y necesita poder escribir el log
mkdir -p /var/log/asterisk
touch /var/log/asterisk/taxi_agi.log
chown asterisk:asterisk /var/log/asterisk/taxi_agi.log

# -------------------------------------------------------------------------
#  7. Reiniciar Asterisk
# -------------------------------------------------------------------------
paso "Reiniciando Asterisk..."
systemctl restart asterisk
sleep 2
if systemctl is-active --quiet asterisk; then
    paso "Asterisk activo."
else
    aviso "Asterisk no levanto. Revisar: journalctl -u asterisk -n 50"
fi

# -------------------------------------------------------------------------
#  Resumen final
# -------------------------------------------------------------------------
IP=$(hostname -I | awk '{print $1}')

echo ""
echo "================================================================"
paso "INSTALACION COMPLETA"
echo "================================================================"
echo ""
echo "Configurar MicroSIP en el PC anfitrion con:"
echo ""
echo "  Servidor (SIP server): $IP"
echo "  Usuario:               1001"
echo "  Password:              TaxiPass1001!"
echo ""
echo "Despues marcar:"
echo "  100  -> servicio de taxis (AGI)"
echo "  600  -> echo test (verificar que el audio funciona)"
echo "  1002 -> llamada al softphone secundario"
echo ""
echo "Para ver logs en vivo:"
echo "  sudo asterisk -rvvvv"
echo "  sudo tail -f /var/log/asterisk/taxi_agi.log"
echo ""
