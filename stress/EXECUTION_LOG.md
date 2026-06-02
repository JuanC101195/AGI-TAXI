# Bitácora de ejecución — Entrega 2 (Load Testing)

> Este archivo registra el punto exacto donde quedamos en cada sesión, para poder retomar sin repetir trabajo. Actualizar al cierre de cada sesión.

## Estado actual: **Setup en la VM a medias — bloqueado por mirror de apt**

**Fecha última sesión:** 2026-06-01

### Lo que YA está hecho

- [x] Rama `feature/stress-test` creada y pusheada con todos los artefactos (`stress/asterisk`, `stress/sipp`, `stress/scripts`, `stress/latex`).
- [x] `README.md` del repo actualizado (sección 11 enlaza a `stress/`).
- [x] LaTeX `stress/latex/entrega2.tex` cubre la rúbrica (config + evidencias).
- [x] VM `taxi-agi` arrancada y validada:
  - Asterisk **20.19.0** corriendo en `2026-05-06`.
  - IPs: `192.168.56.10` (host-only, target de PJSIP) y `192.168.68.110` (NAT/bridged).
  - Endpoints `1001` y `1002` activos (1001 con contacto, 1002 unavailable).
  - El AGI `taxi_agi.py` funciona (logs muestran reservas confirmadas/canceladas).
- [x] Repo clonado en la VM en `/home/lenovo/so-taxi-agi`.

### Lo que está BLOQUEADO

- [ ] `git` no está instalado en la VM y `sudo apt install git` falla:
  ```
  http://deb.debian.org/debian/pool/main/c/curl/libcurl3t64-gnutls_8.14.1-2+deb13u2_amd64.deb
  404 Not Found
  ```
  El mirror Debian tiene la versión desincronizada. **Solución pendiente**: cambiar mirror a `ftp.us.debian.org`.

### Próximos pasos al retomar (en este orden)

#### 1. Arrancar VM y loguearse como `lenovo`

```powershell
# En PowerShell de Windows:
# (si VBoxManage falla por COM, abrir VirtualBox GUI a mano: Win → "virtualbox" → doble click taxi-agi)
& "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe" startvm taxi-agi --type gui
```

#### 2. Desbloquear apt + instalar git

```bash
cd ~/so-taxi-agi
sudo sed -i 's|deb.debian.org|ftp.us.debian.org|g' /etc/apt/sources.list
sudo apt update
sudo apt install -y git
git --version    # debe responder
```

#### 3. Traer la rama y aplicar config

```bash
git fetch origin
git checkout feature/stress-test
ls stress/       # README.md asterisk latex results scripts sipp

cd stress/scripts
chmod +x *.sh
sudo ./install-tools.sh
sudo ./apply-config.sh
sudo asterisk -rx 'pjsip show endpoint 6000'       # debe aparecer
sudo asterisk -rx 'dialplan show from-stress'      # debe listar 7000 y 7100
```

#### 4. Validación 1 llamada (smoke test)

```bash
cd ../sipp
sipp -sf uac-echo-no-rtp.xml -s 7000 127.0.0.1:5060 \
     -au 6000 -ap 'StressPass6000!' \
     -l 1 -r 1 -m 1 -trace_err
# Debe terminar con "Successful call 1"
```

#### 5. Detectar interfaz para monitor.sh

```bash
ip -br link      # buscar la interfaz host-only (suele ser enp0s8 o similar)
# Si es distinto a enp0s8, exportar IFACE antes de monitor.sh:
#   IFACE=enp0sX sudo ./monitor.sh ...
```

#### 6. Rampa de carga

**Terminal A — monitor (sudo porque llama a asterisk -rx):**
```bash
cd ~/so-taxi-agi/stress/scripts
mkdir -p ../results
sudo IFACE=enp0s8 ./monitor.sh ../results/monitor.csv    # ajusta IFACE
```

**Terminal B — runner:**
```bash
cd ~/so-taxi-agi/stress/scripts
./run-load.sh                  # escenario Echo (7000)
SERVICE=7100 ./run-load.sh     # escenario AGI (7100)
```

#### 7. Gráficas + LaTeX

```bash
python3 plot.py ../results/monitor.csv ../results/
cd ../latex
cp ../results/cpu_vs_channels.png placeholder_cpu.png
cp ../results/network.png          placeholder_net.png
# Editar tab:resultados en entrega2.tex con datos de ../results/*/summary.csv
sudo apt install -y texlive-latex-recommended texlive-pictures texlive-lang-spanish texlive-fonts-recommended
pdflatex entrega2.tex && pdflatex entrega2.tex
```

## Datos del entorno (no repetir averiguación)

| Dato | Valor |
|---|---|
| VM nombre VirtualBox | `taxi-agi` |
| Usuario VM | `lenovo` |
| Path repo en VM | `/home/lenovo/so-taxi-agi` |
| IP host-only (PJSIP) | `192.168.56.10:5060/UDP` |
| IP NAT/bridge | `192.168.68.110` |
| Versión Asterisk | 20.19.0 (compilada 2026-05-06) |
| Endpoint SIPp (a crear) | `6000` / `StressPass6000!` |
| Extensión Echo | `7000` |
| Extensión AGI | `7100` |
| Mirror apt que funciona | `ftp.us.debian.org` |
| Path repo en Windows | `C:\Users\LeNoVo\so-taxi-agi` |

## PR pendiente

Abrir manualmente en: https://github.com/JuanC101195/AGI-TAXI/pull/new/feature/stress-test
(O ejecutar `gh auth login` en Windows y luego `gh pr create --base main --head feature/stress-test`).
