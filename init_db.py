#!/usr/bin/env python3
"""
Inicializa la BD SQLite con datos demo para el AGI de taxis.

Crea (o re-crea) las tablas:
  - taxis(id, placa, zip_code, disponible)
  - reservas(id, taxi_id, documento, zip_code, estado, creada_en)

E inserta 10 taxis de ejemplo distribuidos en 5 zip codes de Medellin
(050001, 050010, 050020, 050030, 050040).

Idempotente: borra contenido y re-pobla. Correr una sola vez al instalar
o cuando se quieran resetear los datos demo.
"""

import os
import sqlite3
import sys

DB_PATH = "/var/lib/asterisk/agi-bin/taxis.db"

SCHEMA = """
CREATE TABLE IF NOT EXISTS taxis (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    placa       TEXT    NOT NULL UNIQUE,
    zip_code    TEXT    NOT NULL,
    disponible  INTEGER NOT NULL DEFAULT 1
);

CREATE INDEX IF NOT EXISTS idx_taxis_zip ON taxis(zip_code, disponible);

CREATE TABLE IF NOT EXISTS reservas (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    taxi_id     INTEGER NOT NULL,
    documento   TEXT    NOT NULL,
    zip_code    TEXT    NOT NULL,
    estado      TEXT    NOT NULL DEFAULT 'ACTIVA',
    creada_en   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (taxi_id) REFERENCES taxis(id)
);
"""

# Placas inventadas, todas con el formato colombiano: 3 letras + 3 digitos.
# Distribuidos: 2 taxis por zip code para que las pruebas tengan margen.
TAXIS_DEMO = [
    ("TBC123", "050001"),
    ("XYZ456", "050001"),
    ("DEF789", "050010"),
    ("GHI012", "050010"),
    ("JKL345", "050020"),
    ("MNO678", "050020"),
    ("PQR901", "050030"),
    ("STU234", "050030"),
    ("VWX567", "050040"),
    ("YZA890", "050040"),
]


def main():
    # Asegurar que el directorio existe (relevante en la VM real).
    db_dir = os.path.dirname(DB_PATH)
    if db_dir and not os.path.exists(db_dir):
        os.makedirs(db_dir, exist_ok=True)

    conn = sqlite3.connect(DB_PATH)
    try:
        cur = conn.cursor()
        cur.executescript(SCHEMA)
        cur.execute("DELETE FROM reservas")
        cur.execute("DELETE FROM taxis")
        cur.executemany(
            "INSERT INTO taxis (placa, zip_code) VALUES (?, ?)",
            TAXIS_DEMO,
        )
        conn.commit()

        # Mostrar resumen
        cur.execute("SELECT COUNT(*) FROM taxis")
        total = cur.fetchone()[0]
        cur.execute("SELECT zip_code, COUNT(*) FROM taxis GROUP BY zip_code")
        por_zip = cur.fetchall()
    finally:
        conn.close()

    print(f"BD creada en: {DB_PATH}")
    print(f"Total taxis: {total}")
    print("Distribucion por zip code:")
    for zip_code, cantidad in por_zip:
        print(f"  {zip_code}: {cantidad}")


if __name__ == "__main__":
    try:
        main()
    except sqlite3.Error as e:
        print(f"Error de BD: {e}", file=sys.stderr)
        sys.exit(1)
