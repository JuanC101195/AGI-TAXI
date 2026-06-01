#!/usr/bin/env python3
"""
plot.py

Genera dos graficas en PNG a partir del CSV producido por monitor.sh:
  1) CPU (usr+sys+iow) vs tiempo, con el numero de canales de Asterisk
     superpuesto en eje secundario.
  2) Trafico de red (RX/TX en kbps) vs tiempo.

Uso:
  python3 plot.py monitor.csv salida_dir/
"""
import csv
import sys
from pathlib import Path

try:
    import matplotlib.pyplot as plt
except ImportError:
    sys.stderr.write("Instala matplotlib: pip install matplotlib\n")
    sys.exit(1)


def load(csv_path: Path):
    rows = []
    with csv_path.open() as f:
        for r in csv.DictReader(f):
            rows.append(r)
    return rows


def main():
    if len(sys.argv) != 3:
        sys.stderr.write("Uso: plot.py <monitor.csv> <out_dir>\n")
        sys.exit(1)

    csv_path = Path(sys.argv[1])
    out_dir = Path(sys.argv[2])
    out_dir.mkdir(parents=True, exist_ok=True)

    rows = load(csv_path)
    if not rows:
        sys.stderr.write("CSV vacio\n")
        sys.exit(1)

    t0 = int(rows[0]["timestamp"])
    t = [int(r["timestamp"]) - t0 for r in rows]
    cpu = [float(r["cpu_usr"]) + float(r["cpu_sys"]) + float(r["cpu_iow"]) for r in rows]
    chans = [int(r["ast_channels"]) for r in rows]
    rx = [int(r["net_rx_kbps"]) for r in rows]
    tx = [int(r["net_tx_kbps"]) for r in rows]

    fig, ax1 = plt.subplots(figsize=(10, 4.5))
    ax1.plot(t, cpu, label="CPU usr+sys+iow (%)", color="tab:red")
    ax1.set_xlabel("Tiempo (s)")
    ax1.set_ylabel("CPU (%)", color="tab:red")
    ax1.set_ylim(0, 100)
    ax1.tick_params(axis="y", labelcolor="tab:red")
    ax1.grid(True, linestyle=":", alpha=0.5)

    ax2 = ax1.twinx()
    ax2.plot(t, chans, label="Canales activos", color="tab:blue")
    ax2.set_ylabel("Canales Asterisk", color="tab:blue")
    ax2.tick_params(axis="y", labelcolor="tab:blue")

    fig.suptitle("CPU vs concurrencia durante la prueba de carga")
    fig.tight_layout()
    fig.savefig(out_dir / "cpu_vs_channels.png", dpi=150)

    fig2, ax = plt.subplots(figsize=(10, 4.5))
    ax.plot(t, rx, label="RX (kbps)")
    ax.plot(t, tx, label="TX (kbps)")
    ax.set_xlabel("Tiempo (s)")
    ax.set_ylabel("kbps")
    ax.grid(True, linestyle=":", alpha=0.5)
    ax.legend()
    fig2.suptitle("Trafico SIP/RTP durante la prueba de carga")
    fig2.tight_layout()
    fig2.savefig(out_dir / "network.png", dpi=150)

    print(f"Generadas {out_dir/'cpu_vs_channels.png'} y {out_dir/'network.png'}")


if __name__ == "__main__":
    main()
