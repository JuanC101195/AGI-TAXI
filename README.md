# Sistema de Consulta de Disponibilidad de Taxi por Voz

**Curso:** Seminario de Voz IP
**Universidad:** Universidad de Antioquia
**Tema del proyecto AGI:** _Sistema de consulta de disponibilidad de taxi y registro de usuario y dirección de recogida._

> El sistema recibe el número de documento del usuario y el zip-code del área de recogida, y responde por voz con la disponibilidad del taxi más cercano indicando la placa. Si no hay taxis en el área, lo informa. También ofrece la opción de cancelar la reserva.

---

## 1. Descripción

Construimos un servicio telefónico que un cliente llama, navega un menú por DTMF, y obtiene en voz la placa de un taxi disponible en su zona. Todo el flujo de conversación lo maneja un script AGI (Asterisk Gateway Interface) en Python que se comunica con Asterisk vía STDIN/STDOUT y consulta una base de datos SQLite local.

Decidimos usar AGI (no IVR puro en el dialplan) porque la lógica de "buscar y reservar un taxi" naturalmente se modela en código, y AGI es exactamente el puente que Asterisk ofrece para delegar lógica de negocio a un programa externo.

---

## 2. Cumplimiento del enunciado

Mapeamos punto por punto del enunciado contra lo que entrega el sistema:

| Requerimiento | Cómo lo resolvimos |
|---|---|
| Recibir el **número de documento** del usuario | El AGI captura DTMF con `GET DATA`, terminado en `#`, máximo 12 dígitos. |
| Recibir el **zip-code** del área de recogida | Idem, máximo 6 dígitos. |
| **Responder con la disponibilidad** del taxi más cercano | Query SQL contra `taxis` filtrando por zip y `disponible = 1`. |
| **Indicar la placa** del taxi | `SAY ALPHA` para las letras + `SAY DIGITS` para los números (lectura dígito por dígito). |
| Si **no hay disponible**, informarlo | Audio `no_disponible.wav` y se despide. |
| Ofrecer **cancelar la reserva** | Después de la placa, menú: `1` confirmar / `2` cancelar. Cancelar libera el taxi en la BD. |

---

## 3. Arquitectura del sistema

```
┌────────────────────────────┐
│  Cliente (softphone)       │
│  MicroSIP en Windows       │
└────────────┬───────────────┘
             │ SIP/RTP por la red
             ▼
┌────────────────────────────┐
│  Asterisk (PBX)            │
│  Debian 13 dentro de la VM │
│  - extensions.conf         │
│  - pjsip.conf              │
└────────────┬───────────────┘
             │ AGI (STDIN/STDOUT)
             ▼
┌────────────────────────────┐
│  taxi_agi.py               │
│  (Python 3)                │
└────────────┬───────────────┘
             │ SQL
             ▼
┌────────────────────────────┐
│  taxis.db (SQLite)         │
│  - taxis(placa, zip, disp) │
│  - reservas(estado, ...)   │
└────────────────────────────┘
```

Cuando un usuario marca la extensión `100`, Asterisk identifica esa extensión en `extensions.conf` y dispara el script AGI. El script toma el control del canal, reproduce audios pregrabados (TTS español hecho con `espeak`), captura DTMF, consulta SQLite, y al terminar devuelve el control a Asterisk para que cuelgue.

---

## 4. Flujo de la conversación

```
Usuario marca 100
        │
        ▼
[1] Bot: "Bienvenido al servicio de taxis. Marque su número de documento + #"
        │
        ▼ Usuario marca DTMF
[2] Bot: "Marque el código postal del área de recogida + #"
        │
        ▼ Usuario marca DTMF
        ▼
        ▼ El AGI consulta la BD
        │
   ┌────┴────┐
   │         │
   SÍ        NO
   │         │
   ▼         ▼
[3a]       [3b] Bot: "No hay taxis disponibles..."
Bot: "Tenemos un taxi disponible. La placa es: T-B-C-1-2-3"
   │
   ▼
[4] Bot: "Marque 1 para confirmar, 2 para cancelar"
        │
   ┌────┴────┐
   │         │
   1         2
   │         │
   ▼         ▼
[5a]       [5b] Bot: "Reserva cancelada" (libera el taxi)
Bot: "Reserva confirmada"
   │
   ▼
[6] Bot: "Gracias por usar nuestro servicio"
```

---

## 5. Tecnologías y por qué

| Componente | Elección | Justificación |
|---|---|---|
| PBX | **Asterisk 18+** | Estándar de facto en VoIP open-source; lo trabajamos en clase. |
| Lenguaje del AGI | **Python 3** | Sintaxis simple; con `sqlite3` + `re` + `logging` de la stdlib alcanza, no requiere instalar dependencias extra en la VM. |
| Base de datos | **SQLite** | Cero overhead operativo: un solo archivo, sin servidor de BD aparte. Suficiente para el alcance del proyecto. |
| TTS de prompts fijos | **espeak + sox** | Generamos los audios en español al instalar y los dejamos como WAV de 8 kHz mono PCM, formato esperado por Asterisk. |
| TTS de la placa | **SAY ALPHA + SAY DIGITS** | Voces internas de Asterisk; las usamos en runtime para deletrear la placa específica del taxi asignado. |
| Softphone cliente | **MicroSIP** | Gratis, liviano (~5 MB), corre en el host Windows. |
| SO de la VM | **Debian 13 (Trixie)** | Estable y con `asterisk` empaquetado en repositorios oficiales (`apt install`). |

---

## 6. Componentes del proyecto

```
so-taxi-agi/
├── README.md             ← este archivo
├── taxi_agi.py           ← script AGI principal (lógica del bot)
├── init_db.py            ← inicializa la BD SQLite con datos demo
├── extensions.conf       ← dialplan de Asterisk
├── pjsip.conf            ← usuarios SIP
├── instalar.sh           ← deploy automático en la VM
└── .gitignore
```

### `taxi_agi.py` — el cerebro

Implementa el protocolo AGI directo (sin librerías externas):

- Lee variables del canal por STDIN al inicio.
- Envía comandos AGI por STDOUT (`STREAM FILE`, `GET DATA`, `SAY ALPHA`, `SAY DIGITS`).
- Loguea todo a `/var/log/asterisk/taxi_agi.log` para depurar.
- Implementa la máquina de estados del flujo (paso 1 a 6).

### `init_db.py` — datos demo

Crea dos tablas:

```sql
CREATE TABLE taxis (
    id          INTEGER PRIMARY KEY,
    placa       TEXT UNIQUE,
    zip_code    TEXT,
    disponible  INTEGER  -- 1 = libre, 0 = ocupado
);

CREATE TABLE reservas (
    id          INTEGER PRIMARY KEY,
    taxi_id     INTEGER,
    documento   TEXT,
    zip_code    TEXT,
    estado      TEXT,  -- ACTIVA, CANCELADA
    creada_en   TIMESTAMP
);
```

Y siembra **10 taxis demo** en 5 zip-codes de Medellín, dos taxis por zona.

### `extensions.conf` — dialplan

Asocia extensiones a acciones:
- `100` → ejecuta `AGI(taxi_agi.py)` (servicio de taxis).
- `600` → echo test (sirve para verificar audio).
- `1001` / `1002` → llamadas internas entre softphones (útil para validar que Asterisk responde antes de probar el AGI).

### `pjsip.conf` — usuarios SIP

Define dos extensiones (`1001`, `1002`) con sus credenciales para que MicroSIP se registre desde el host Windows.

### `instalar.sh` — automatiza el deploy

Hace todo de un solo paso dentro de la VM:
1. `apt install asterisk python3 espeak sox`.
2. Copia los scripts AGI a `/var/lib/asterisk/agi-bin/`.
3. Inicializa la BD.
4. Genera los audios en español con `espeak` + `sox` (los deja en `/var/lib/asterisk/sounds/custom/taxi/`).
5. Copia `extensions.conf` y `pjsip.conf` a `/etc/asterisk/`.
6. Ajusta permisos y reinicia Asterisk.

---

## 7. Cómo levantarlo

### En el host (Windows)

Necesitamos:
- VirtualBox 7.x
- MicroSIP (softphone)
- ISO de Debian 12/13 netinst

### En la VM (Debian)

Una vez instalado Debian con SSH server y utilidades estándar, copiamos los archivos del proyecto y corremos:

```bash
chmod +x instalar.sh
sudo ./instalar.sh
```

Al final el script imprime la IP de la VM y los datos para configurar MicroSIP:
- **Servidor SIP:** la IP de la VM
- **Usuario:** `1001`
- **Password:** `TaxiPass1001!`

### Probar

Con MicroSIP registrado, marcamos:
- **`100`** → servicio de taxis (el AGI completo)
- **`600`** → echo test (chequea audio bidireccional)

---

## 8. Datos de prueba

| Zip code | Taxis cargados |
|---|---|
| `050001` | TBC123, XYZ456 |
| `050010` | DEF789, GHI012 |
| `050020` | JKL345, MNO678 |
| `050030` | PQR901, STU234 |
| `050040` | VWX567, YZA890 |

Marcar un zip code distinto a esos prueba el caso "no hay taxis disponibles".

Para resetear la BD durante una demo (si pruebas anteriores ocuparon todos los taxis), ejecutamos:

```bash
sudo python3 /var/lib/asterisk/agi-bin/init_db.py
```

---

## 9. Logs útiles para depurar

Durante una llamada, podemos abrir paralelamente:

```bash
# Consola interactiva de Asterisk (vemos cada paso del dialplan):
sudo asterisk -rvvvv

# Log del AGI Python (lo que va imprimiendo nuestro script):
sudo tail -f /var/log/asterisk/taxi_agi.log

# Log general de Asterisk:
sudo tail -f /var/log/asterisk/full
```

---

## 10. Posibles extensiones (fuera del alcance del entregable)

Quedaron como ideas que no entran en esta versión por tiempo, pero que serían el siguiente paso natural:

- Reconocimiento de voz en lugar de DTMF (con un servicio TTS/STT externo).
- API REST para consultar reservas desde una app de despachadores.
- Geolocalización del taxi en lugar de zip code estático.
- Notificación SMS al cliente cuando el taxi llega.
- Cancelación remota: que el cliente vuelva a llamar y cancele una reserva activa marcando su documento.
