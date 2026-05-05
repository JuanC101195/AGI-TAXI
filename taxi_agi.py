#!/usr/bin/env python3
"""
Sistema de consulta de disponibilidad de taxis - AGI para Asterisk
==================================================================

Flujo:
  1. Saluda y pide el numero de documento (DTMF, terminado en #).
  2. Pide el codigo postal de recogida (DTMF, terminado en #).
  3. Consulta SQLite buscando un taxi disponible en ese zip code.
  4. Si hay -> reproduce la placa (letras + digitos) y pide confirmar/cancelar.
  5. Si no hay -> avisa y se despide.

Asterisk invoca este script desde el dialplan con AGI(taxi_agi.py).
La comunicacion con Asterisk es por STDIN/STDOUT (protocolo AGI).
"""

import sys
import os
import re
import sqlite3
import logging

# ----------------------------------------------------------------------
# Configuracion
# ----------------------------------------------------------------------
DB_PATH = "/var/lib/asterisk/agi-bin/taxis.db"

# Asterisk busca audios en /var/lib/asterisk/sounds/. El prefijo "custom/taxi"
# apunta a la subcarpeta donde instalar.sh deja los WAV generados con espeak.
SOUNDS = "custom/taxi"

LOG_FILE = "/var/log/asterisk/taxi_agi.log"


def _configure_logging():
    """
    Configura logging hacia archivo. Tolerante a entornos donde el path
    de Asterisk no existe (por ejemplo el host Windows durante pruebas):
    en ese caso loguea a stderr, que Asterisk descarta.

    Importante: NO loguear a stdout porque stdout es el canal AGI.
    """
    fmt = "%(asctime)s [%(levelname)s] %(message)s"
    try:
        handler = logging.FileHandler(LOG_FILE)
    except (OSError, FileNotFoundError):
        handler = logging.StreamHandler(sys.stderr)
    handler.setFormatter(logging.Formatter(fmt))
    logger = logging.getLogger("taxi_agi")
    logger.setLevel(logging.INFO)
    if not logger.handlers:
        logger.addHandler(handler)
    return logger


log = _configure_logging()


# ----------------------------------------------------------------------
# Capa AGI minima (sin librerias externas)
# ----------------------------------------------------------------------
class AGI:
    """
    Implementacion ligera del protocolo AGI.

    - El primer bloque que envia Asterisk son variables clave:valor
      seguidas de una linea vacia (las leemos en _read_env).
    - Cada comando se envia por stdout, terminado en \\n, y leemos
      una linea por stdin con la respuesta tipo "200 result=<x>".
    - stderr se ignora del lado de Asterisk; lo usamos para logging
      auxiliar si hace falta.
    """

    def __init__(self):
        self.env = self._read_env()
        log.info("=" * 60)
        log.info(
            "AGI iniciado | canal=%s | callerid=%s",
            self.env.get("agi_channel"),
            self.env.get("agi_callerid"),
        )

    def _read_env(self):
        env = {}
        while True:
            line = sys.stdin.readline()
            if not line:
                break
            line = line.rstrip("\n")
            if line == "":
                break
            if ":" in line:
                k, v = line.split(":", 1)
                env[k.strip()] = v.strip()
        return env

    def _send(self, cmd):
        log.debug("CMD -> %s", cmd)
        sys.stdout.write(cmd + "\n")
        sys.stdout.flush()
        resp = sys.stdin.readline().strip()
        log.debug("RES <- %s", resp)
        return resp

    # --- Helpers de alto nivel ----------------------------------------

    def play(self, sound):
        """Reproduce un audio sin esperar input."""
        return self._send(f'STREAM FILE {sound} ""')

    def get_data(self, sound, timeout=10000, max_digits=15):
        """
        Reproduce un audio de prompt y captura DTMF hasta:
          - que el usuario marque #,
          - alcance max_digits, o
          - venza el timeout (en milisegundos).
        Devuelve la cadena de digitos ingresada (sin el # final).
        """
        resp = self._send(f"GET DATA {sound} {timeout} {max_digits}")
        m = re.search(r"result=(\S+)", resp)
        return m.group(1) if m and m.group(1) != "-1" else ""

    def say_alpha(self, text):
        """Deletrea texto letra por letra."""
        return self._send(f'SAY ALPHA {text} ""')

    def say_digits(self, digits):
        """Lee un numero digito por digito."""
        return self._send(f'SAY DIGITS {digits} ""')

    def hangup(self):
        return self._send("HANGUP")


# ----------------------------------------------------------------------
# Capa de datos (SQLite)
# ----------------------------------------------------------------------
def buscar_taxi(zip_code):
    """Devuelve el primer taxi disponible en ese zip code, o None."""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT * FROM taxis WHERE zip_code = ? AND disponible = 1 LIMIT 1",
            (zip_code,),
        )
        row = cur.fetchone()
        return dict(row) if row else None
    finally:
        conn.close()


def reservar_taxi(taxi_id, documento, zip_code):
    """Marca el taxi como ocupado y crea la reserva. Devuelve el id de la reserva."""
    conn = sqlite3.connect(DB_PATH)
    try:
        cur = conn.cursor()
        cur.execute("UPDATE taxis SET disponible = 0 WHERE id = ?", (taxi_id,))
        cur.execute(
            "INSERT INTO reservas (taxi_id, documento, zip_code, estado) "
            "VALUES (?, ?, ?, 'ACTIVA')",
            (taxi_id, documento, zip_code),
        )
        reserva_id = cur.lastrowid
        conn.commit()
        return reserva_id
    finally:
        conn.close()


def cancelar_reserva(taxi_id):
    """Libera el taxi y marca la reserva activa como cancelada."""
    conn = sqlite3.connect(DB_PATH)
    try:
        cur = conn.cursor()
        cur.execute("UPDATE taxis SET disponible = 1 WHERE id = ?", (taxi_id,))
        cur.execute(
            "UPDATE reservas SET estado = 'CANCELADA' "
            "WHERE taxi_id = ? AND estado = 'ACTIVA'",
            (taxi_id,),
        )
        conn.commit()
    finally:
        conn.close()


# ----------------------------------------------------------------------
# Logica del bot
# ----------------------------------------------------------------------
def split_placa(placa):
    """
    Separa una placa colombiana tipo 'TBC123' en ('TBC', '123') para
    que SAY ALPHA + SAY DIGITS la lean correctamente. Si el formato no
    matchea, devuelve la placa entera para SAY ALPHA y vacio para digitos.
    """
    m = re.match(r"^([A-Za-z]+)(\d+)$", placa.strip())
    if m:
        return m.group(1).upper(), m.group(2)
    return placa.strip().upper(), ""


def main():
    agi = AGI()
    try:
        # 1. Pedir documento
        documento = agi.get_data(f"{SOUNDS}/bienvenida", timeout=15000, max_digits=12)
        if not documento:
            log.warning("Sin documento. Aborta.")
            agi.play(f"{SOUNDS}/no_input")
            return
        log.info("Documento: %s", documento)

        # 2. Pedir zip code
        zip_code = agi.get_data(f"{SOUNDS}/pedir_zip", timeout=15000, max_digits=6)
        if not zip_code:
            log.warning("Sin zip code. Aborta.")
            agi.play(f"{SOUNDS}/no_input")
            return
        log.info("Zip code: %s", zip_code)

        # 3. Consulta de disponibilidad
        taxi = buscar_taxi(zip_code)
        if not taxi:
            log.info("No hay taxi disponible en zip %s", zip_code)
            agi.play(f"{SOUNDS}/no_disponible")
            agi.play(f"{SOUNDS}/despedida")
            return

        log.info("Taxi encontrado id=%s placa=%s", taxi["id"], taxi["placa"])

        # 4. Reservar y comunicar la placa
        reserva_id = reservar_taxi(taxi["id"], documento, zip_code)
        agi.play(f"{SOUNDS}/taxi_disponible")
        letras, digitos = split_placa(taxi["placa"])
        if letras:
            agi.say_alpha(letras)
        if digitos:
            agi.say_digits(digitos)

        # 5. Confirmar o cancelar
        opcion = agi.get_data(f"{SOUNDS}/confirmar", timeout=10000, max_digits=1)
        if opcion == "1":
            log.info("Reserva %s CONFIRMADA", reserva_id)
            agi.play(f"{SOUNDS}/confirmada")
        elif opcion == "2":
            log.info("Reserva %s CANCELADA por el usuario", reserva_id)
            cancelar_reserva(taxi["id"])
            agi.play(f"{SOUNDS}/cancelada")
        else:
            # Sin respuesta: cancelamos automaticamente para liberar el taxi.
            log.info("Reserva %s cancelada por timeout sin respuesta", reserva_id)
            cancelar_reserva(taxi["id"])
            agi.play(f"{SOUNDS}/cancelada")

        agi.play(f"{SOUNDS}/despedida")

    except Exception:
        log.exception("Error inesperado en el AGI")
    finally:
        log.info("AGI termino")


if __name__ == "__main__":
    main()
