# Sistema de Consulta de Taxi por Voz (Asterisk + AGI)

Proyecto para el curso **Seminario de Voz IP**.

El usuario llama a una extensión, marca su número de documento y un código postal, y el sistema le dice por voz la placa del taxi disponible más cercano. Si no hay taxi en la zona, se lo informa. Después permite confirmar o cancelar la reserva.

## Componentes

| Archivo | Rol |
|---|---|
| `taxi_agi.py` | Script AGI en Python que ejecuta Asterisk en cada llamada. Es el cerebro. |
| `init_db.py` | Crea la BD SQLite con 10 taxis demo distribuidos en 5 zip codes de Medellín. |
| `extensions.conf` | Dialplan de Asterisk. Asocia la extensión `100` al AGI. |
| `pjsip.conf` | Define los usuarios SIP (`1001`, `1002`) que se conectan con MicroSIP. |
| `instalar.sh` | Automatiza todo el deploy dentro de la VM Debian (apt, copias, BD, audios, restart). |

## Flujo de la llamada

```
Usuario marca 100
        │
        ▼
┌─────────────────────────────────────────────┐
│  Asterisk recibe la llamada                 │
│  → lee extensions.conf                      │
│  → exec AGI(taxi_agi.py)                    │
└─────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────┐
│  taxi_agi.py (Python)                       │
│  1. "Marque su documento + #"               │
│  2. "Marque el zip code + #"                │
│  3. SELECT FROM taxis WHERE zip_code = ?    │
│       AND disponible = 1                    │
│  4a. Si hay → reserva + dice la placa       │
│       (SAY ALPHA + SAY DIGITS)              │
│       → "1 confirmar / 2 cancelar"          │
│  4b. Si no hay → "no hay disponibles"       │
│  5. Despedida y cuelga                      │
└─────────────────────────────────────────────┘
```

## Stack

- **PBX:** Asterisk 18+ sobre Debian 12 (instalado vía `apt`).
- **AGI:** Python 3 sin dependencias externas (solo stdlib + sqlite3).
- **BD:** SQLite (un solo archivo, sin servidor de BD aparte).
- **TTS:** `espeak` + `sox` (al instalar genera los audios fijos en español).
- **Softphone cliente:** MicroSIP (en el host Windows).

## Setup paso a paso

### 1. En el host (Windows) — ya hecho

- VirtualBox 7.2.8 instalado
- MicroSIP 3.22.3 instalado
- Python 3.14 instalado (para validar localmente)
- Debian 12 netinst ISO descargado en `~/Downloads/debian-12-netinst.iso`

### 2. Crear la VM en VirtualBox

Recomendado:
- Nombre: `taxi-agi`
- Tipo: Linux / Debian (64-bit)
- RAM: 1024 MB (alcanza)
- Disco: 10 GB dinámico (VDI)
- Red: **Adaptador puente** (importante: NAT no permite que MicroSIP llegue a la VM)
- Boot ISO: `debian-12-netinst.iso`

Durante la instalación de Debian:
- Instalación estándar (puede ser sin entorno gráfico).
- Anotar el usuario y password creados.
- Marcar **"openssh-server"** y **"standard system utilities"** en la selección de software (los demás opcionales).
- Apagar la VM al terminar.

### 3. Compartir los archivos del proyecto a la VM

Tres opciones, escogé la que te resulte más fácil:

#### A) Carpeta compartida de VirtualBox (más simple)

En la VM apagada → Configuración → Carpetas compartidas → agregar `C:\Users\LeNoVo\so-taxi-agi` con punto de montaje `/mnt/proyecto`, marcar "Automontar". Después en la VM:

```bash
sudo usermod -aG vboxsf $USER
sudo reboot
# Despues del reboot:
ls /media/sf_so-taxi-agi/   # o /mnt/proyecto, segun como lo montó
```

#### B) `scp` desde el host

Saber la IP de la VM con `ip a` dentro de ella. Desde el host (PowerShell):

```powershell
scp C:\Users\LeNoVo\so-taxi-agi\* usuario@<IP-VM>:/home/usuario/proyecto_taxi/
```

#### C) Git (si tenés el proyecto en un repo)

```bash
git clone <url-del-repo>
```

### 4. Correr el instalador dentro de la VM

```bash
cd ~/proyecto_taxi    # o donde hayas dejado los archivos
chmod +x instalar.sh
sudo ./instalar.sh
```

El script imprime al final la IP de la VM y los datos de conexión SIP.

### 5. Configurar MicroSIP en el host

Abrir MicroSIP → menú → "Add Account":
- **SIP Server:** la IP que imprimió `instalar.sh`
- **Username:** `1001`
- **Password:** `TaxiPass1001!`
- **Domain:** la misma IP (o dejarlo vacío)
- Codecs: dejar `ulaw` y `alaw`

Cuando el indicador de la cuenta queda en verde, marcar `100` y apretar el botón verde de llamar.

### 6. Probar

1. **Echo test (`600`)** primero — si funciona, el audio del softphone está OK.
2. **Servicio de taxis (`100`)** — el flow completo:
   - Te pide documento → marca por ej. `12345678#`
   - Te pide zip code → marca `050001#` (hay 2 taxis en ese zip)
   - Te dice "La placa es: T-B-C-1-2-3"
   - Te pide confirmar/cancelar → marca `1` para confirmar.

### 7. Logs útiles

```bash
# Consola interactiva de Asterisk (muy útil para debugging):
sudo asterisk -rvvvv

# Log del AGI:
sudo tail -f /var/log/asterisk/taxi_agi.log

# Log de Asterisk:
sudo tail -f /var/log/asterisk/full
```

## Datos demo

`init_db.py` siembra 10 taxis con esta distribución:

| Zip code | Taxis | Placas |
|---|---|---|
| `050001` | 2 | TBC123, XYZ456 |
| `050010` | 2 | DEF789, GHI012 |
| `050020` | 2 | JKL345, MNO678 |
| `050030` | 2 | PQR901, STU234 |
| `050040` | 2 | VWX567, YZA890 |

Marcar un zip code distinto a esos prueba el caso "no hay taxis disponibles".

## Para resetear la BD durante una demo

Si querés volver a tener todos los taxis disponibles (después de pruebas que ocuparon varios):

```bash
sudo python3 /var/lib/asterisk/agi-bin/init_db.py
```

## Sobre la sustentación

Puntos a destacar al profesor:

- **AGI = Asterisk Gateway Interface**: protocolo que permite a Asterisk delegar lógica de negocio a un script externo (en este caso Python). El script lee STDIN, escribe STDOUT, recibe variables del canal y envía comandos como `STREAM FILE`, `GET DATA`, `SAY ALPHA`, `SAY DIGITS`.
- **Por qué Python**: stdlib de sobra para el caso (sqlite3, regex, logging), no requiere instalar dependencias adicionales en la VM.
- **Por qué SQLite**: cero overhead operativo, persistente, suficiente para el alcance.
- **TTS dinámico vs audios pregrabados**: la placa se lee en runtime (`SAY ALPHA TBC` + `SAY DIGITS 123`) usando las voces internas de Asterisk; los prompts fijos son audios .wav generados con espeak en español.
- **Cancelación**: la opción 2 del menú revierte la reserva (taxi vuelve a `disponible = 1` y la fila de `reservas` queda con `estado = 'CANCELADA'`).

## Estructura interna de la BD

```sql
CREATE TABLE taxis (
    id          INTEGER PRIMARY KEY,
    placa       TEXT UNIQUE,
    zip_code    TEXT,
    disponible  INTEGER  -- 0 ocupado, 1 libre
);

CREATE TABLE reservas (
    id          INTEGER PRIMARY KEY,
    taxi_id     INTEGER,
    documento   TEXT,
    zip_code    TEXT,
    estado      TEXT,  -- ACTIVA, CANCELADA, COMPLETADA
    creada_en   TIMESTAMP
);
```
